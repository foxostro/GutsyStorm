//
// File:        GLString.m
//                (Originally StringTexture.m)
//
// Abstract:    Uses Quartz to draw a string into an OpenGL texture
//
// Version:        1.1 - Antialiasing option, Rounded Corners to the frame
//                      self contained OpenGL state, performance enhancements,
//                      other bug fixes.
//                1.0 - Original release.
//                
//
// Disclaimer:    IMPORTANT:  This Apple software is supplied to you by Apple Inc. ("Apple")
//                in consideration of your agreement to the following terms, and your use,
//                installation, modification or redistribution of this Apple software
//                constitutes acceptance of these terms.  If you do not agree with these
//                terms, please do not use, install, modify or redistribute this Apple
//                software.
//
//                In consideration of your agreement to abide by the following terms, and
//                subject to these terms, Apple grants you a personal, non - exclusive
//                license, under Apple's copyrights in this original Apple software ( the
//                "Apple Software" ), to use, reproduce, modify and redistribute the Apple
//                Software, with or without modifications, in source and / or binary forms;
//                provided that if you redistribute the Apple Software in its entirety and
//                without modifications, you must retain this notice and the following text
//                and disclaimers in all such redistributions of the Apple Software. Neither
//                the name, trademarks, service marks or logos of Apple Inc. may be used to
//                endorse or promote products derived from the Apple Software without specific
//                prior written permission from Apple.  Except as expressly stated in this
//                notice, no other rights or licenses, express or implied, are granted by
//                Apple herein, including but not limited to any patent rights that may be
//                infringed by your derivative works or by other works in which the Apple
//                Software may be incorporated.
//
//                The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
//                WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
//                WARRANTIES OF NON - INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A
//                PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION
//                ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
//
//                IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
//                CONSEQUENTIAL DAMAGES ( INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//                SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//                INTERRUPTION ) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION
//                AND / OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER
//                UNDER THEORY OF CONTRACT, TORT ( INCLUDING NEGLIGENCE ), STRICT LIABILITY OR
//                OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// Copyright ( C ) 2003-2007 Apple Inc. All Rights Reserved.
//

#import "GLString.h"
#import "GSShader.h"
#import "GSVBOHolder.h"
#import <simd/matrix.h>

// The following is a NSBezierPath category to allow
// for rounded corners of the border

#pragma mark -
#pragma mark NSBezierPath Category

@implementation NSBezierPath (RoundRect)

+ (nonnull NSBezierPath *)bezierPathWithRoundedRect:(NSRect)rect cornerRadius:(float)radius {
    NSBezierPath *result = [NSBezierPath bezierPath];
    [result appendBezierPathWithRoundedRect:rect cornerRadius:radius];
    return result;
}

- (void)appendBezierPathWithRoundedRect:(NSRect)rect cornerRadius:(float)radius {
    if (!NSIsEmptyRect(rect)) {
        if (radius > 0.0) {
            // Clamp radius to be no larger than half the rect's width or height.
            float clampedRadius = MIN(radius, 0.5 * MIN(rect.size.width, rect.size.height));
            
            NSPoint topLeft = NSMakePoint(NSMinX(rect), NSMaxY(rect));
            NSPoint topRight = NSMakePoint(NSMaxX(rect), NSMaxY(rect));
            NSPoint bottomRight = NSMakePoint(NSMaxX(rect), NSMinY(rect));
            
            [self moveToPoint:NSMakePoint(NSMidX(rect), NSMaxY(rect))];
            [self appendBezierPathWithArcFromPoint:topLeft     toPoint:rect.origin radius:clampedRadius];
            [self appendBezierPathWithArcFromPoint:rect.origin toPoint:bottomRight radius:clampedRadius];
            [self appendBezierPathWithArcFromPoint:bottomRight toPoint:topRight    radius:clampedRadius];
            [self appendBezierPathWithArcFromPoint:topRight    toPoint:topLeft     radius:clampedRadius];
            [self closePath];
        } else {
            // When radius == 0.0, this degenerates to the simple case of a plain rectangle.
            [self appendBezierPathWithRect:rect];
        }
    }
}

@end


#pragma mark -
#pragma mark GLString

// GLString follows

@implementation GLString
{
    CGLContextObj _cgl_ctx; // current context at time of texture creation
    GLuint _texName;
    NSSize _texSize;

    NSAttributedString * _string;
    NSColor * _textColor; // default is opaque white
    NSColor * _boxColor; // default transparent or none
    NSColor * _borderColor; // default transparent or none
    BOOL _staticFrame; // default in NO
    BOOL _antialias;    // default to YES
    NSSize _marginSize; // offset or frame size, default is 4 width 2 height
    NSSize _frameSize; // offset or frame size, default is 4 width 2 height
    float    _cRadius; // Corner radius, if 0 just a rectangle. Defaults to 4.0f
    
    GSShader *_shader;
    GSVBOHolder *_vbo;

    BOOL _requiresUpdate;
}

#pragma mark -
#pragma mark Deallocs

- (void) deleteTexture
{
    if (_texName && _cgl_ctx) {
        (*_cgl_ctx->disp.delete_textures)(_cgl_ctx->rend, 1, &_texName);
        _texName = 0; // ensure it is zeroed for failure cases
        _cgl_ctx = 0;
    }
}

- (void) dealloc
{
    [self deleteTexture];
}

#pragma mark -
#pragma mark Initializers

// designated initializer
- (nonnull instancetype) initWithAttributedString:(nonnull NSAttributedString *)attributedString
                                     withTextColor:(nonnull NSColor *)text
                                      withBoxColor:(nonnull NSColor *)box
                                   withBorderColor:(nonnull NSColor *)border
{
    self = [super init];
    if (self) {
        // Initialization code here.
        _cgl_ctx = NULL;
        _texName = 0;
        _texSize.width = 0.0f;
        _texSize.height = 0.0f;
        _string = attributedString;
        _textColor = text;
        _boxColor = box;
        _borderColor = border;
        _staticFrame = NO;
        _antialias = YES;
        _marginSize.width = 4.0f; // standard margins
        _marginSize.height = 2.0f;
        _cRadius = 4.0f;
        _requiresUpdate = YES;
        // all other variables 0 or NULL
    }
    
    return self;
}

- (nonnull instancetype) initWithString:(nonnull NSString *)aString
                          withAttributes:(nonnull NSDictionary<NSString *, id> *)attribs
                           withTextColor:(nonnull NSColor *)text
                            withBoxColor:(nonnull NSColor *)box
                         withBorderColor:(nonnull NSColor *)border
{
    NSAttributedString *attr = [[NSAttributedString alloc] initWithString:aString attributes:attribs];
    return [self initWithAttributedString:attr withTextColor:text withBoxColor:box withBorderColor:border];
}

// basic methods that pick up defaults
- (nonnull instancetype) initWithAttributedString:(nonnull NSAttributedString *)attributedString;
{
    return [self initWithAttributedString:attributedString withTextColor:[NSColor colorWithDeviceRed:1.0f green:1.0f blue:1.0f alpha:1.0f] withBoxColor:[NSColor colorWithDeviceRed:1.0f green:1.0f blue:1.0f alpha:0.0f] withBorderColor:[NSColor colorWithDeviceRed:1.0f green:1.0f blue:1.0f alpha:0.0f]];
}

- (nonnull instancetype) initWithString:(nonnull NSString *)aString
                          withAttributes:(nonnull NSDictionary<NSString *, id> *)attribs
{
    return [self initWithAttributedString:[[NSAttributedString alloc] initWithString:aString attributes:attribs] withTextColor:[NSColor colorWithDeviceRed:1.0f green:1.0f blue:1.0f alpha:1.0f] withBoxColor:[NSColor colorWithDeviceRed:1.0f green:1.0f blue:1.0f alpha:0.0f] withBorderColor:[NSColor colorWithDeviceRed:1.0f green:1.0f blue:1.0f alpha:0.0f]];
}

- (void) genTexture; // generates the texture without drawing texture to current context
{
    NSImage * image;
    NSBitmapImageRep * bitmap;
    
    NSSize previousSize = _texSize;
    
    if ((NO == _staticFrame) && (0.0f == _frameSize.width) && (0.0f == _frameSize.height)) { // find frame size if we have not already found it
        _frameSize = [_string size]; // current string size
        _frameSize.width += _marginSize.width * 2.0f; // add padding
        _frameSize.height += _marginSize.height * 2.0f;
    }
    image = [[NSImage alloc] initWithSize:_frameSize];
    
    [image lockFocus];
    [[NSGraphicsContext currentContext] setShouldAntialias:_antialias];
    
    if ([_boxColor alphaComponent]) { // this should be == 0.0f but need to make sure
        [_boxColor set]; 
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(NSMakeRect (0.0f, 0.0f, _frameSize.width, _frameSize.height) , 0.5, 0.5)
                                                        cornerRadius:_cRadius];
        [path fill];
    }

    if ([_borderColor alphaComponent]) {
        [_borderColor set]; 
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(NSMakeRect (0.0f, 0.0f, _frameSize.width, _frameSize.height), 0.5, 0.5) 
                                                        cornerRadius:_cRadius];
        [path setLineWidth:1.0f];
        [path stroke];
    }
    
    [_textColor set]; 
    [_string drawAtPoint:NSMakePoint (_marginSize.width, _marginSize.height)]; // draw at offset position
    bitmap = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect (0.0f, 0.0f, _frameSize.width, _frameSize.height)];
    [image unlockFocus];
    _texSize.width = [bitmap pixelsWide];
    _texSize.height = [bitmap pixelsHigh];
    
    _cgl_ctx = CGLGetCurrentContext();
    if (_cgl_ctx) { // if we successfully retrieve a current context (required)
        glPushAttrib(GL_TEXTURE_BIT);
        if (0 == _texName) glGenTextures (1, &_texName);
        glBindTexture (GL_TEXTURE_RECTANGLE_EXT, _texName);
        if (NSEqualSizes(previousSize, _texSize)) {
            glTexSubImage2D(GL_TEXTURE_RECTANGLE_EXT,0,0,0,_texSize.width,_texSize.height,[bitmap hasAlpha] ? GL_RGBA : GL_RGB,GL_UNSIGNED_BYTE,[bitmap bitmapData]);
        } else {
            glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA, _texSize.width, _texSize.height, 0, [bitmap hasAlpha] ? GL_RGBA : GL_RGB, GL_UNSIGNED_BYTE, [bitmap bitmapData]);
        }
        glPopAttrib();
    } else
        NSLog (@"StringTexture -genTexture: Failure to get current OpenGL context\n");
    
    _requiresUpdate = NO;
}

#pragma mark -
#pragma mark Accessors

- (GLuint) texName
{
    return _texName;
}

- (NSSize) texSize
{
    return _texSize;
}

#pragma mark Text Color

- (void) setTextColor:(nonnull NSColor *)color // set default text color
{
    _textColor = color;
    _requiresUpdate = YES;
}

- (NSColor *) textColor
{
    return _textColor;
}

#pragma mark Box Color

- (void) setBoxColor:(nonnull NSColor *)color // set default text color
{
    _boxColor = color;
    _requiresUpdate = YES;
}

- (NSColor *) boxColor
{
    return _boxColor;
}

#pragma mark Border Color

- (void) setBorderColor:(nonnull NSColor *)color // set default text color
{
    _borderColor = color;
    _requiresUpdate = YES;
}

- (NSColor *) borderColor
{
    return _borderColor;
}

#pragma mark Margin Size

// these will force the texture to be regenerated at the next draw
- (void) setMargins:(NSSize)size // set offset size and size to fit with offset
{
    _marginSize = size;
    if (NO == _staticFrame) { // ensure dynamic frame sizes will be recalculated
        _frameSize.width = 0.0f;
        _frameSize.height = 0.0f;
    }
    _requiresUpdate = YES;
}

- (NSSize) marginSize
{
    return _marginSize;
}

#pragma mark Antialiasing
- (BOOL) antialias
{
    return _antialias;
}

- (void) setAntialias:(bool)request
{
    _antialias = request;
    _requiresUpdate = YES;
}


#pragma mark Frame

- (NSSize) frameSize
{
    if ((NO == _staticFrame) && (0.0f == _frameSize.width) && (0.0f == _frameSize.height)) { // find frame size if we have not already found it
        _frameSize = [_string size]; // current string size
        _frameSize.width += _marginSize.width * 2.0f; // add padding
        _frameSize.height += _marginSize.height * 2.0f;
    }
    return _frameSize;
}

- (BOOL) staticFrame
{
    return _staticFrame;
}

- (void) useStaticFrame:(NSSize)size // set static frame size and size to frame
{
    _frameSize = size;
    _staticFrame = YES;
    _requiresUpdate = YES;
}

- (void) useDynamicFrame
{
    if (_staticFrame) { // set to dynamic frame and set to regen texture
        _staticFrame = NO;
        _frameSize.width = 0.0f; // ensure frame sizes will be recalculated
        _frameSize.height = 0.0f;
        _requiresUpdate = YES;
    }
}

#pragma mark String

- (void) setString:(nonnull NSAttributedString *)attributedString // set string after initial creation
{
    _string = attributedString;
    if (NO == _staticFrame) { // ensure dynamic frame sizes will be recalculated
        _frameSize.width = 0.0f;
        _frameSize.height = 0.0f;
    }
    _requiresUpdate = YES;
}

// set string after initial creation
- (void) setString:(nonnull NSString *)aString withAttributes:(nonnull NSDictionary<NSString *, id> *)attribs
{
    [self setString:[[NSAttributedString alloc] initWithString:aString attributes:attribs]];
}


#pragma mark -
#pragma mark Drawing

- (void) drawWithBounds:(NSRect)bounds withModelViewProjectionMatrix:(matrix_float4x4)mvp
{
    vector_float4 vertices[] = {
        (vector_float4){0.0f,           0.0f,            bounds.origin.x,                     bounds.origin.y},
        (vector_float4){0.0f,           _texSize.height, bounds.origin.x,                     bounds.origin.y + bounds.size.height},
        (vector_float4){_texSize.width, _texSize.height, bounds.origin.x + bounds.size.width, bounds.origin.y + bounds.size.height},
        (vector_float4){_texSize.width, 0.0f,            bounds.origin.x + bounds.size.width, bounds.origin.y}
    };

    if (_requiresUpdate) {
        [self genTexture];
    }

    if (_texName) {
        glPushAttrib(GL_ENABLE_BIT | GL_TEXTURE_BIT | GL_COLOR_BUFFER_BIT);
        glActiveTexture(GL_TEXTURE0);
        glEnable(GL_TEXTURE_2D);
        glBindTexture (GL_TEXTURE_RECTANGLE_EXT, _texName);
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_TEXTURE_RECTANGLE_EXT);
        glDisable(GL_DEPTH_TEST);
        glEnable(GL_TEXTURE_RECTANGLE_EXT);

        [_shader bind];
        [_shader bindUniformWithMatrix4x4:mvp name:@"mvp"];
        [_shader bindUniformWithInt:0 name:@"tex"];
        
        glBindBuffer(GL_ARRAY_BUFFER, _vbo.handle);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
        glVertexPointer(4, GL_FLOAT, 0, 0);
        glEnableClientState(GL_VERTEX_ARRAY);
        glDrawArrays(GL_QUADS, 0, 4);
        glDisableClientState(GL_VERTEX_ARRAY);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
        [_shader unbind];

        glPopAttrib();
    }
}

- (void) drawAtPoint:(NSPoint)point withModelViewProjectionMatrix:(matrix_float4x4)mvp
{
    if (!_vbo) {
        GLuint handle = 0;
        glGenBuffers(1, &handle);
        _vbo = [[GSVBOHolder alloc] initWithHandle:handle context:[NSOpenGLContext currentContext]];
    }

    if (!_shader) {
        NSBundle *bundle = [NSBundle bundleWithIdentifier:[[NSRunningApplication currentApplication] bundleIdentifier]];
        NSString *vertFn = [bundle pathForResource:@"text.vert" ofType:@"txt"];
        NSString *fragFn = [bundle pathForResource:@"text.frag" ofType:@"txt"];
        NSString *vertSrc = [[NSString alloc] initWithContentsOfFile:vertFn encoding:NSMacOSRomanStringEncoding error:nil];
        NSString *fragSrc = [[NSString alloc] initWithContentsOfFile:fragFn encoding:NSMacOSRomanStringEncoding error:nil];
        _shader = [[GSShader alloc] initWithVertexShaderSource:vertSrc fragmentShaderSource:fragSrc];
    }

    if (_requiresUpdate) {
        [self genTexture]; // ensure size is calculated for bounds
    }

    if (_texName) { // if successful
        NSRect bounds = NSMakeRect (point.x, point.y, _texSize.width, _texSize.height);
        [self drawWithBounds:bounds withModelViewProjectionMatrix:mvp];
    }
}

@end
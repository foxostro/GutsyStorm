//
//  GSVBOHolder.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

// Holds an OpenGL vertex buffer object, allowing it to be reference counted.
@interface GSVBOHolder : NSObject

@property (nonatomic, readonly) GLuint handle;

- (nonnull instancetype)initWithHandle:(GLuint)handle context:(nonnull NSOpenGLContext *)context;

@end

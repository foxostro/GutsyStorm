//
//  GSChunkVBOs.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

@class GSChunkGeometryData;

@interface GSChunkVBOs : NSObject <GSGridItem>

- (id)initWithChunkGeometry:(GSChunkGeometryData *)geometry
                  glContext:(NSOpenGLContext *)glContext;

- (void)draw;

@end

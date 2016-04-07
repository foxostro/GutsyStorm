//
//  GSChunkVAO.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

@class GSChunkGeometryData;

@interface GSChunkVAO : NSObject <GSGridItem>

/* May return nil if the necessary GPU resources could not be reserved. */
- (nullable instancetype)initWithChunkGeometry:(nonnull GSChunkGeometryData *)geometry
                                     glContext:(nonnull NSOpenGLContext *)glContext;

/* Assumes the caller has already locked the context on the current thread. */
- (void)draw;

@end

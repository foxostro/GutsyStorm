//
//  GSByteBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import "GSByteBuffer.h"
#import "Chunk.h"


static void samplingPoints(size_t count, GLKVector3 *sample, GSIntegerVector3 normal);


@implementation GSByteBuffer

- (id)initWithDimensions:(GSIntegerVector3)dim
{
    self = [super init];
    if (self) {
        assert(dim.x >= CHUNK_SIZE_X);
        assert(dim.y >= CHUNK_SIZE_Y);
        assert(dim.z >= CHUNK_SIZE_Z);

        _dimensions = dim;

        _offsetFromChunkLocalSpace = GSIntegerVector3_Make((dim.x - CHUNK_SIZE_X) / 2,
                                                           (dim.y - CHUNK_SIZE_Y) / 2,
                                                           (dim.z - CHUNK_SIZE_Z) / 2);

        _data = malloc(BUFFER_SIZE_IN_BYTES);

        if(!_data) {
            [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for lighting buffer."];
        }

        bzero(_data, BUFFER_SIZE_IN_BYTES);
    }
    
    return self;
}

- (id)initWithDimensions:(GSIntegerVector3)dim data:(uint8_t *)data
{
    assert(data);
    self = [self initWithDimensions:dim];
    if (self) {
        memcpy(_data, data, BUFFER_SIZE_IN_BYTES);
    }

    return self;
}

- (void)dealloc
{
    free(_data);
}

- (uint8_t)valueAtPoint:(GSIntegerVector3)chunkLocalPos
{
    assert(_data);

    GSIntegerVector3 p = GSIntegerVector3_Add(chunkLocalPos, _offsetFromChunkLocalSpace);

    if(p.x >= 0 && p.x < self.dimensions.x &&
       p.y >= 0 && p.y < self.dimensions.y &&
       p.z >= 0 && p.z < self.dimensions.z) {
        return _data[INDEX_INTO_LIGHTING_BUFFER(p)];
    } else {
        return 0;
    }
}

- (uint8_t)lightForVertexAtPoint:(GLKVector3)vertexPosInWorldSpace
                      withNormal:(GSIntegerVector3)normal
                            minP:(GLKVector3)minP
{
    static const size_t count = 4;
    GLKVector3 sample[count];
    float light;
    int i;

    assert(_data);

    samplingPoints(count, sample, normal);

    for(light = 0.0f, i = 0; i < count; ++i)
    {
        GSIntegerVector3 clp = GSIntegerVector3_Make(truncf(sample[i].x + vertexPosInWorldSpace.x - minP.x),
                                                     truncf(sample[i].y + vertexPosInWorldSpace.y - minP.y),
                                                     truncf(sample[i].z + vertexPosInWorldSpace.z - minP.z));

        assert(clp.x >= -1 && clp.x <= CHUNK_SIZE_X);
        assert(clp.y >= -1 && clp.y <= CHUNK_SIZE_Y);
        assert(clp.z >= -1 && clp.z <= CHUNK_SIZE_Z);

        light += [self valueAtPoint:clp] / (float)count;
    }
    
    return light;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[GSByteBuffer allocWithZone:zone] initWithDimensions:_dimensions data:_data];
}

@end


static void samplingPoints(size_t count, GLKVector3 *sample, GSIntegerVector3 n)
{
    assert(count == 4);
    assert(sample);

    const float a = 0.5f;

    if(n.x==1 && n.y==0 && n.z==0) {
        sample[0] = GLKVector3Make(+a, -a, -a);
        sample[1] = GLKVector3Make(+a, -a, +a);
        sample[2] = GLKVector3Make(+a, +a, -a);
        sample[3] = GLKVector3Make(+a, +a, +a);
    } else if(n.x==-1 && n.y==0 && n.z==0) {
        sample[0] = GLKVector3Make(-a, -a, -a);
        sample[1] = GLKVector3Make(-a, -a, +a);
        sample[2] = GLKVector3Make(-a, +a, -a);
        sample[3] = GLKVector3Make(-a, +a, +a);
    } else if(n.x==0 && n.y==1 && n.z==0) {
        sample[0] = GLKVector3Make(-a, +a, -a);
        sample[1] = GLKVector3Make(-a, +a, +a);
        sample[2] = GLKVector3Make(+a, +a, -a);
        sample[3] = GLKVector3Make(+a, +a, +a);
    } else if(n.x==0 && n.y==-1 && n.z==0) {
        sample[0] = GLKVector3Make(-a, -a, -a);
        sample[1] = GLKVector3Make(-a, -a, +a);
        sample[2] = GLKVector3Make(+a, -a, -a);
        sample[3] = GLKVector3Make(+a, -a, +a);
    } else if(n.x==0 && n.y==0 && n.z==1) {
        sample[0] = GLKVector3Make(-a, -a, +a);
        sample[1] = GLKVector3Make(-a, +a, +a);
        sample[2] = GLKVector3Make(+a, -a, +a);
        sample[3] = GLKVector3Make(+a, +a, +a);
    } else if(n.x==0 && n.y==0 && n.z==-1) {
        sample[0] = GLKVector3Make(-a, -a, -a);
        sample[1] = GLKVector3Make(-a, +a, -a);
        sample[2] = GLKVector3Make(+a, -a, -a);
        sample[3] = GLKVector3Make(+a, +a, -a);
    } else {
        assert(!"shouldn't get here");
        sample[0] = GLKVector3Make(0, 0, 0);
        sample[1] = GLKVector3Make(0, 0, 0);
        sample[2] = GLKVector3Make(0, 0, 0);
        sample[3] = GLKVector3Make(0, 0, 0);
    }
}
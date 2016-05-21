//
//  GSTerrainGeometry.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/21/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainGeometry.h"


GSTerrainGeometry * _Nonnull GSTerrainGeometryCreate(void)
{
    GSTerrainGeometry *geometry = malloc(sizeof(GSTerrainGeometry));
    if(!geometry) {
        [NSException raise:NSMallocException format:@"Out of memory while allocating `geometry'"];
    }
    
    geometry->capacity = 1;
    geometry->count = 0;
    geometry->vertices = malloc(sizeof(GSTerrainVertex) * geometry->capacity);
    if(!geometry->vertices) {
        [NSException raise:NSMallocException format:@"Out of memory while allocating `geometry->vertices'"];
    }
    
    return geometry;
}


void GSTerrainGeometryDestroy(GSTerrainGeometry * _Nullable geometry)
{
    if (geometry) {
        free(geometry->vertices);
        free(geometry);
    }
}


GSTerrainGeometry * _Nonnull GSTerrainGeometryCopy(GSTerrainGeometry * _Nonnull original)
{
    assert(original);

    GSTerrainGeometry *geometry = malloc(sizeof(GSTerrainGeometry));
    if(!geometry) {
        [NSException raise:NSMallocException format:@"Out of memory while allocating `geometry'"];
    }

    geometry->capacity = original->capacity;
    geometry->count = original->count;
    geometry->vertices = malloc(sizeof(GSTerrainVertex) * original->capacity);
    if(!geometry->vertices) {
        [NSException raise:NSMallocException format:@"Out of memory while allocating `geometry->vertices'"];
    }

    memcpy(geometry->vertices, original->vertices, sizeof(GSTerrainVertex) * original->count);

    return geometry;
}


void GSTerrainGeometryAddVertex(GSTerrainGeometry * _Nonnull geometry, GSTerrainVertex * _Nonnull vertex)
{
    assert(geometry);
    assert(vertex);
    assert(geometry->count <= geometry->capacity);
    
    if ((geometry->count == geometry->capacity) || (geometry->capacity == 0)) {
        geometry->capacity = (geometry->capacity == 0) ? 1 : (geometry->capacity * 2);
        geometry->vertices = reallocf(geometry->vertices, geometry->capacity * sizeof(GSTerrainVertex));
        if(!geometry->vertices) {
            [NSException raise:NSMallocException format:@"Out of memory while enlarging geometry->vertices."];
        }
    }

    geometry->vertices[geometry->count] = *vertex;
    geometry->count++;
}
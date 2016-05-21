//
//  GSTerrainGeometry.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/21/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>

#import "GSTerrainVertex.h"


typedef struct
{
    GSTerrainVertex * _Nullable vertices;
    size_t capacity;
    size_t count;
} GSTerrainGeometry;


GSTerrainGeometry * _Nonnull GSTerrainGeometryCreate(void);
void GSTerrainGeometryDestroy(GSTerrainGeometry * _Nullable geometry);
GSTerrainGeometry * _Nonnull GSTerrainGeometryCopy(GSTerrainGeometry * _Nonnull original);
void GSTerrainGeometryAddVertex(GSTerrainGeometry * _Nonnull geometry, GSTerrainVertex * _Nonnull vertex);

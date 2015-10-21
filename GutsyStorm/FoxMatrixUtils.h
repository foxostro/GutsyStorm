//
//  FoxMatrixExtra.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/16/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#ifndef MatrixExtra_h
#define MatrixExtra_h

#import <simd/matrix.h>
#import <simd/vector.h>

static inline matrix_float4x4 matrix_from_translation(vector_float3 v)
{
    return (matrix_float4x4){
        (vector_float4){ 1, 0, 0, v.x },
        (vector_float4){ 0, 1, 0, v.y },
        (vector_float4){ 0, 0, 1, v.z },
        (vector_float4){ 0, 0, 0, 1 },
    };
}

static inline matrix_float4x4 matrix_from_scale(vector_float4 v)
{
    return matrix_from_diagonal(v);
}

#endif /* MatrixExtra_h */

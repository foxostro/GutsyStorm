//
//  GSTerrainRayMarcher.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/1/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>
#import "GSRay.h"


@interface GSTerrainRayMarcher : NSObject

- (nonnull instancetype)init NS_DESIGNATED_INITIALIZER;

/* Enumerates the voxels on the specified ray up to the specified maximum depth. Calls the block for each voxel cell.
 * The block may set '*stop=YES;' to indicate that enumeration should terminate with a successful condition. The block
 * may set '*fail=YES;' to indicate that enumeration should terminate with a non-successful condition. Typically, this
 * occurs when the block realizes that it must block to take a lock.
 * Returns YES or NO depending on whether the operation was successful. This method will do its best to avoid blocking
 * (i.e. by waiting to take locks) and will return early if the alternative is to block. In this case, the function
 * returns NO.
 */
- (BOOL)enumerateVoxelsOnRay:(GSRay)ray
                    maxDepth:(unsigned)maxDepth
                   withBlock:(void (^ _Nonnull)(vector_float3 p, BOOL * _Nullable stop, BOOL * _Nullable fail))block;

@end

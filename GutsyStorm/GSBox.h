//
//  GSBox.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/12/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#ifndef GSBox_h
#define GSBox_h

#import "GSIntegerVector3.h"
#import "GSAABB.h"


#define FOR_BOX(p, box) for((p).x = (box).mins.x; (p).x < (box).maxs.x; ++(p).x) \
                                   for((p).y = (box).mins.y; (p).y < (box).maxs.y; ++(p).y) \
                                       for((p).z = (box).mins.z; (p).z < (box).maxs.z; ++(p).z)

#define FOR_Y_COLUMN_IN_BOX(p, box) for((p).y = (box).mins.y, (p).x = (box).mins.x; (p).x < (box).maxs.x; ++(p).x) \
                                             for((p).z = (box).mins.z; (p).z < (box).maxs.z; ++(p).z)


static inline long INDEX_BOX(vector_long3 p, GSIntAABB box)
{
    const long sizeY = box.maxs.y - box.mins.y;
    const long sizeZ = box.maxs.z - box.mins.z;
    
    // Columns in the y-axis are contiguous in memory.
    return ((p.x-box.mins.x)*sizeY*sizeZ) + ((p.z-box.mins.z)*sizeY) + (p.y-box.mins.y);
}


#endif /* GSBox_h */

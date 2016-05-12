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


#define FOR_BOX(p, minP, maxP) for((p).x = (minP).x; (p).x < (maxP).x; ++(p).x) \
                                   for((p).y = (minP).y; (p).y < (maxP).y; ++(p).y) \
                                       for((p).z = (minP).z; (p).z < (maxP).z; ++(p).z)

#define FOR_Y_COLUMN_IN_BOX(p, minP, maxP) for((p).y = (minP).y, (p).x = (minP).x; (p).x < (maxP).x; ++(p).x) \
                                             for((p).z = (minP).z; (p).z < (maxP).z; ++(p).z)


static inline long INDEX_BOX(vector_long3 p, GSIntAABB box)
{
    const long sizeY = box.maxs.y - box.mins.y;
    const long sizeZ = box.maxs.z - box.mins.z;
    
    // Columns in the y-axis are contiguous in memory.
    return ((p.x-box.mins.x)*sizeY*sizeZ) + ((p.z-box.mins.z)*sizeY) + (p.y-box.mins.y);
}

static inline long INDEX_BOX2(vector_long3 p, vector_long3 a, vector_long3 b)
{
    return INDEX_BOX(p, (GSIntAABB){ .mins = a, .maxs = b });
}


#endif /* GSBox_h */

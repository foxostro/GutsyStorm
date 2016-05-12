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


#define FOR_BOX(p, minP, maxP) for((p).x = (minP).x; (p).x < (maxP).x; ++(p).x) \
                                   for((p).y = (minP).y; (p).y < (maxP).y; ++(p).y) \
                                       for((p).z = (minP).z; (p).z < (maxP).z; ++(p).z)

#define FOR_Y_COLUMN_IN_BOX(p, minP, maxP) for((p).y = (minP).y, (p).x = (minP).x; (p).x < (maxP).x; ++(p).x) \
                                             for((p).z = (minP).z; (p).z < (maxP).z; ++(p).z)


static inline long INDEX_BOX(vector_long3 p, vector_long3 minP, vector_long3 maxP)
{
    const long sizeY = maxP.y - minP.y;
    const long sizeZ = maxP.z - minP.z;
    
    // Columns in the y-axis are contiguous in memory.
    return ((p.x-minP.x)*sizeY*sizeZ) + ((p.z-minP.z)*sizeY) + (p.y-minP.y);
}


#endif /* GSBox_h */

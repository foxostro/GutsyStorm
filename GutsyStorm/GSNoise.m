//
//  GSNoise.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSNoise.h"

static const float onethird = 1.0 / 3.0;
static const float onesixth = 1.0 / 6.0;


static int doB2(int N, int B);
static int doB1(int *T, int i, int j, int k, int B);
static int shuffle(int *T, int i, int j, int k);


@interface GSNoise (Private)

- (float)noise:(float)x y:(float)y z:(float)z;
- (float)doK:(int)a;

@end


@implementation GSNoise

- (id)initWithSeed:(unsigned)seed
{
    self = [super init];
    if (self) {
        // Initialization code here.
        A[0] = A[1] = A[2] = 0;
        
        int _T[8] = {0x15, 0x38, 0x32, 0x2c, 0x0d, 0x13, 0x07, 0x2a};
        memcpy(T, _T, sizeof(int)*8);
    }
    
    return self;
}


- (float)getNoiseAtPoint:(GSVector3)p
{
    return [self noise:p.x y:p.y z:p.z] * 2.8; // scale to [-1, +1]
}

@end


@implementation GSNoise (Private)

// returns a value in the range of about [-0.347 .. 0.347]
- (float)noise:(float)x y:(float)y z:(float)z
{
    // Skew input space to relative coordinate in simplex cell
    s = (x + y + z) * onethird;
    i = floorf(x+s);
    j = floorf(y+s);
    k = floorf(z+s);
    
    // Unskew cell origin back to (x, y , z) space
    s = (i + j + k) * onesixth;
    u = x - i + s;
    v = y - j + s;
    w = z - k + s;
    
    A[0] = A[1] = A[2] = 0;
    
    // For 3D case, the simplex shape is a slightly irregular tetrahedron.
    // Determine which simplex we're in
    int hi = u >= w ? u >= v ? 0 : 1 : v >= w ? 1 : 2;
    int lo = u < w ? u < v ? 0 : 1 : v < w ? 1 : 2;
    
    return [self doK:hi] + [self doK:(3 - hi - lo)] + [self doK:lo] + [self doK:0];
}


- (float)doK:(int)a
{
    s = (A[0] + A[1] + A[2]) * onesixth;
    float x = u - A[0] + s;
    float y = v - A[1] + s;
    float z = w - A[2] + s;
    float t = 0.6f - x * x - y * y - z * z;
    int h = shuffle(T, i + A[0], j + A[1], k + A[2]);
    A[a]++;
    if (t < 0) return 0;
    int b5 = h >> 5 & 1;
    int b4 = h >> 4 & 1;
    int b3 = h >> 3 & 1;
    int b2 = h >> 2 & 1;
    int b = h & 3;
    float p = b == 1 ? x : b == 2 ? y : z;
    float q = b == 1 ? y : b == 2 ? z : x;
    float r = b == 1 ? z : b == 2 ? x : y;
    p = b5 == b3 ? -p : p;
    q = b5 == b4 ? -q: q;
    r = b5 != (b4^b3) ? -r : r;
    t *= t;
    return 8 * t * t * (p + (b == 0 ? q + r : b2 == 0 ? q : r));
}

@end


static int doB2(int N, int B)
{
    return N >> B & 1;
}


static int doB1(int *T, int i, int j, int k, int B)
{
    return T[doB2(i, B) << 2 | doB2(j, B) << 1 | doB2(k, B)];
}


static int shuffle(int *T, int i, int j, int k)
{
    return doB1(T, i, j, k, 0) + doB1(T, j, k, i, 1) + doB1(T, k, i, j, 2) + doB1(T, i, j, k, 3) +
    doB1(T, j, k, i, 4) + doB1(T, k, i, j, 5) + doB1(T, i, j, k, 6) + doB1(T, j, k, i, 7);
}
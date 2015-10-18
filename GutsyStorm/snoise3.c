/* snoise3.c
 *
 * This header comment added by Andrew Fox <foxostro@gmail.com> on 2012-03-25.
 *
 * This is a smooth noise generation routine developed by "FeepingCreature"
 * and released on GitHub under the BSD license, with modifications by
 * Andrew Fox.
 *
 * The full text of the license which was included with the code has been
 * included below. The original source code is available on GitHub at:
 * <http://github.com/FeepingCreature/SimplexNoise>
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain this list of conditions
 *       and the following disclaimer.
 *     * Redistributions in binary form must reproduce this list of conditions
 *       and the following disclaimer in the documentation and/or other
 *       materials provided with the distribution.
 *     * The names of its contributors may not be used to endorse or
 *       promote products derived from this software without specific
 *       prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#pragma GCC diagnostic ignored "-Wconversion"

#include <xmmintrin.h>
#include <emmintrin.h>
#include <simd/simd.h>
#include "snoise3.h"

typedef float v4sf __attribute__ ((vector_size (16)));
typedef int v4si __attribute__ ((vector_size (16)));

struct NoiseContext {
    int offsets[8][2][4];
    unsigned char *perm, *mperm; // perm mod 12
};

#define LET(A, B) typeof(B) A = B


static v4sf vec4f(float a, float b, float c, float d) {
    return (v4sf) _mm_set_ps(d, c, b, a);
}

static v4sf vec1_4f(float f) {
    return (v4sf) _mm_set1_ps(f);
}

static int isum(v4si vec) {
    int i[4];
    *(v4si*) &i = vec;
    return i[0] + i[1] + i[2];
}

static float sum3(v4sf vec) {
    float f[4];
    *(v4sf*) &f = vec;
    return f[0] + f[1] + f[2];
}

static float sum4(v4sf vec) {
    float f[4];
    *(v4sf*) &f = vec;
    return f[0] + f[1] + f[2] + f[3];
}

void FeepingCreature_DestroyNoiseContext(struct NoiseContext *nc)
{
    free(nc->perm);
    free(nc->mperm);
}

static void shuffle(unsigned *pseed, unsigned char *array, size_t n)
{
    if(n <= 1) {
        return;
    }
    
    for(size_t i = 0; i < n - 1; i++) 
    {
        size_t j = i + rand_r(pseed) / (RAND_MAX / (n - i) + 1);
        unsigned char t = array[j];
        array[j] = array[i];
        array[i] = t;
    }
}

struct NoiseContext *FeepingCreature_CreateNoiseContext(unsigned *pseed)
{
    int i, k, l;
    
    struct NoiseContext *nc = malloc(sizeof(struct NoiseContext));
    
    nc->perm = malloc(sizeof(unsigned char) * 256);
    nc->mperm = malloc(sizeof(unsigned char) * 256);
    
    {
        unsigned char permfill[256] = {162, 43, 153, 52, 83, 210, 193, 75, 227, 195, 233, 76, 83, 48, 252, 181, 101, 31, 13, 32, 38, 23, 72, 101, 100, 145, 105, 218, 135, 89, 39, 100, 162, 196, 51, 18, 185, 138, 76, 83, 228, 229, 128, 101, 76, 111, 68, 227, 114, 123, 72, 98, 219, 161, 8, 86, 212, 50, 219, 166, 139, 195, 195, 128, 74, 250, 154, 110, 150, 175, 36, 25, 96, 123, 101, 12, 236, 158, 227, 199, 77, 156, 6, 159, 203, 92, 27, 60, 155, 218, 239, 156, 184, 90, 213, 115, 38, 18, 39, 102, 191, 87, 177, 47, 64, 28, 224, 252, 176, 9, 111, 208, 112, 50, 78, 123, 243, 248, 99, 112, 52, 142, 253, 93, 30, 111, 56, 104, 217, 3, 204, 188, 144, 143, 155, 228, 55, 249, 45, 9, 152, 26, 250, 2, 135, 30, 4, 169, 30, 208, 56, 255, 15, 123, 237, 170, 17, 71, 182, 203, 246, 162, 184, 164, 103, 77, 49, 174, 186, 159, 201, 216, 41, 92, 246, 158, 112, 79, 99, 101, 231, 46, 88, 81, 94, 23, 24, 103, 43, 224, 151, 173, 217, 142, 64, 78, 203, 110, 151, 49, 22, 107, 3, 44, 110, 151, 253, 142, 125, 247, 3, 239, 42, 23, 238, 102, 114, 104, 58, 227, 164, 31, 214, 84, 98, 159, 67, 181, 19, 144, 133, 213, 19, 122, 245, 42, 217, 205, 0, 87, 104, 122, 35, 238, 96, 93, 116, 177, 56, 201, 147, 156, 229, 219, 16, 128};
        
        // Shuffle the permutation table to give us different noise for every seed.
        shuffle(pseed, permfill, 256);
        
        for (i = 0; i < 256; ++i) {
            nc->perm[i] = permfill[i];
            nc->mperm[i] = nc->perm[i] % 12;
        }
    }
    
    static int offs_init[8][2][4]
    = {
        {{1, 0, 0, 0}, {1, 1, 0, 0}},
        {{0, 1, 0, 0}, {1, 1, 0, 0}},
        {{0, 0, 0, 0}, {0, 0, 0, 0}},
        {{0, 1, 0, 0}, {0, 1, 1, 0}},
        {{1, 0, 0, 0}, {1, 0, 1, 0}},
        {{0, 0, 0, 0}, {0, 0, 0, 0}},
        {{0, 0, 1, 0}, {1, 0, 1, 0}},
        {{0, 0, 1, 0}, {0, 1, 1, 0}}
    };
    for (i = 0; i < 8; ++i)
        for (k = 0; k < 2; ++k)
            for (l = 0; l < 4; ++l)
                nc->offsets[i][k][l] = offs_init[i][k][l];
    
    return nc;
}

float FeepingCreature_noise3(vector_float3 p, struct NoiseContext *nc) {
    v4sf vs[4], vsum;
    int gi[4], mask, c;
    v4sf v = vec4f(p.x, p.y, p.z, 0);
    v4si indices;
    
    vsum = v + vec1_4f(sum3(v) / 3);
    indices = _mm_sub_epi32 (__builtin_ia32_cvttps2dq(vsum), __builtin_ia32_psrldi128 ((v4si) vsum, 31));
    vs[0] = v - __builtin_ia32_cvtdq2ps(indices) + vec1_4f(isum(indices) / 6.0f);
    vs[1] = vs[0] + vec1_4f(     1.0f/6.0f);
    vs[2] = vs[0] + vec1_4f(     2.0f/6.0f);
    vs[3] = vs[0] + vec1_4f(-1.0f + 3.0f/6.0f);
    v4sf xxy = _mm_shuffle_ps(vs[0], vs[0], _MM_SHUFFLE(0, 1, 0, 0));
    v4sf yzz = _mm_shuffle_ps(vs[0], vs[0], _MM_SHUFFLE(0, 2, 2, 1));
    mask = __builtin_ia32_movmskps(_mm_cmplt_ps(xxy, yzz));
    LET(opp, &nc->offsets[mask & 7]);
#define op (*opp)
#define offs1 (op[0])
#define offs2 (op[1])
    vs[1] -= __builtin_ia32_cvtdq2ps(*(v4si*)&offs1);
    vs[2] -= __builtin_ia32_cvtdq2ps(*(v4si*)&offs2);
    int indexfield[4]; *(typeof(indices)*) indexfield = indices;
#define ii indexfield[0]
#define jj indexfield[1]
#define kk indexfield[2]
#define i1 offs1[0]
#define i2 offs2[0]
#define j1 offs1[1]
#define j2 offs2[1]
#define k1 offs1[2]
#define k2 offs2[2]
    LET(mperm, nc->mperm);
    LET(perm, nc->perm);
    gi[0] = mperm[(perm[(perm[(kk   )&0xff]+jj   )&0xff]+ii   )&0xff];
    gi[1] = mperm[(perm[(perm[(kk+k1)&0xff]+jj+j1)&0xff]+ii+i1)&0xff];
    gi[2] = mperm[(perm[(perm[(kk+k2)&0xff]+jj+j2)&0xff]+ii+i2)&0xff];
    gi[3] = mperm[(perm[(perm[(kk+1 )&0xff]+jj+1 )&0xff]+ii+1 )&0xff];
    float factors[4];
    float pair[3], res[4];
    pair[0] = 1; pair[1] = -1; pair[2] = -1;
    for (c = 0; c < 4; ++c) {
        LET(vscp, &(vs[c]));
        LET(current, *vscp);
        {
            LET(A, current * current);
            LET(B, _mm_shuffle_ps(A, A, _MM_SHUFFLE(1, 1, 1, 1)));
            LET(C, _mm_shuffle_ps(A, A, _MM_SHUFFLE(2, 2, 2, 2)));
            LET(D, A + B + C);
            LET(E, vec1_4f(0.6f) - D);
            factors[c] = *(float*) &E;
        }
        if (factors[c] >= 0) {
            int id = gi[c];
            res[c] = (((float*)vscp)[id >> 3] * pair[id & 1]) + (((float*)vscp)[(((id >> 2) | (id >> 3)) & 1) + 1] * pair[id&2]);
        } else {
            factors[c] = 0;
            res[c] = 0;
        }
    }
    v4sf vfactors = vec4f(factors[0], factors[1], factors[2], factors[3]);
    vfactors *= vfactors;
    vfactors *= vfactors;
    v4sf vres = vec4f(res[0], res[1], res[2], res[3]);
    vres *= vfactors;
    return 0.5f + 16 * sum4(vres);
}

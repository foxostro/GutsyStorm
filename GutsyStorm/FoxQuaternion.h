#import <simd/vector.h>

static inline vector_float4 quaternion_make_with_angle_and_axis(float radians, float x, float y, float z)
{
    float ha = radians / 2.0f;
    float scale = sinf(ha);
    vector_float4 q = { scale * x, scale * y, scale * z, cosf(ha) };
    return q;
}

static inline vector_float4 quaternion_multiply(vector_float4 quaternionLeft, vector_float4 quaternionRight)
{
    const __m128 ql = _mm_load_ps((float *)&quaternionLeft);
    const __m128 qr = _mm_load_ps((float *)&quaternionRight);
    
    const __m128 ql3012 = _mm_shuffle_ps(ql, ql, _MM_SHUFFLE(2, 1, 0, 3));
    const __m128 ql3120 = _mm_shuffle_ps(ql, ql, _MM_SHUFFLE(0, 2, 1, 3));
    const __m128 ql3201 = _mm_shuffle_ps(ql, ql, _MM_SHUFFLE(1, 0, 2, 3));
    
    const __m128 qr0321 = _mm_shuffle_ps(qr, qr, _MM_SHUFFLE(1, 2, 3, 0));
    const __m128 qr1302 = _mm_shuffle_ps(qr, qr, _MM_SHUFFLE(2, 0, 3, 1));
    const __m128 qr2310 = _mm_shuffle_ps(qr, qr, _MM_SHUFFLE(0, 1, 3, 2));
    const __m128 qr3012 = _mm_shuffle_ps(qr, qr, _MM_SHUFFLE(2, 1, 0, 3));
    
    uint32_t signBit = 0x80000000;
    uint32_t zeroBit = 0x0;
    uint32_t __attribute__((aligned(16))) mask0001[4] = {zeroBit, zeroBit, zeroBit, signBit};
    uint32_t __attribute__((aligned(16))) mask0111[4] = {zeroBit, signBit, signBit, signBit};
    const __m128 m0001 = _mm_load_ps((float *)mask0001);
    const __m128 m0111 = _mm_load_ps((float *)mask0111);
    
    const __m128 aline = ql3012 * _mm_xor_ps(qr0321, m0001);
    const __m128 bline = ql3120 * _mm_xor_ps(qr1302, m0001);
    const __m128 cline = ql3201 * _mm_xor_ps(qr2310, m0001);
    const __m128 dline = ql3012 * _mm_xor_ps(qr3012, m0111);
    const __m128 r = _mm_hadd_ps(_mm_hadd_ps(aline, bline), _mm_hadd_ps(cline, dline));
    
    return *(vector_float4 *)&r;
}

static inline vector_float4 quaternion_invert(vector_float4 quaternion)
{
    const __m128 q = _mm_load_ps((float *)&quaternion);
    const uint32_t signBit = 0x80000000;
    const uint32_t zeroBit = 0x0;
    const uint32_t __attribute__((aligned(16))) mask[4] = {signBit, signBit, signBit, zeroBit};
    const __m128 v_mask = _mm_load_ps((float *)mask);
    const __m128 product = q * q;
    const __m128 halfsum = _mm_hadd_ps(product, product);
    const __m128 v = _mm_xor_ps(q, v_mask) / _mm_hadd_ps(halfsum, halfsum);
    return *(vector_float4 *)&v;
}

static inline vector_float3 quaternion_rotate_vector(vector_float4 quaternion, vector_float3 v)
{
    vector_float4 rotatedQuaternion = (vector_float4){v.x, v.y, v.z, 0.0f};
    rotatedQuaternion = quaternion_multiply(quaternion_multiply(quaternion, rotatedQuaternion), quaternion_invert(quaternion));
    return rotatedQuaternion.xyz;
}
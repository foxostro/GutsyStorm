//
//  snoise3.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/12.
//

struct NoiseContext;

float FeepingCreature_noise3(vector_float3 p, struct NoiseContext * _Nonnull nc);
struct NoiseContext * _Nullable FeepingCreature_CreateNoiseContext(unsigned * _Nonnull pseed);
void FeepingCreature_DestroyNoiseContext(struct NoiseContext * _Nonnull nc);

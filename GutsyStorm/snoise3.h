//
//  snoise3.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/12.
//

struct NoiseContext;

float FeepingCreature_noise3(vector_float3 p, struct NoiseContext *nc);
struct NoiseContext *FeepingCreature_CreateNoiseContext(unsigned *pseed);
void FeepingCreature_DestroyNoiseContext(struct NoiseContext *nc);

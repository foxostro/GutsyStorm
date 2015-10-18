//
//  snoise3.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/12.
//

#ifndef GutsyStorm_snoise3_h
#define GutsyStorm_snoise3_h

struct NoiseContext;

float FeepingCreature_noise3(vector_float3 p, struct NoiseContext *nc);
struct NoiseContext *FeepingCreature_CreateNoiseContext(unsigned *pseed);
void FeepingCreature_DestroyNoiseContext(struct NoiseContext *nc);

#endif

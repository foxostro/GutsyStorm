//
//  snoise3.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/12.
//

#ifndef GutsyStorm_snoise3_h
#define GutsyStorm_snoise3_h

#include "GSVector3.h"

struct NoiseContext;

float FeepingCreature_noise3(GSVector3 p, struct NoiseContext *nc);
struct NoiseContext *FeepingCreature_CreateNoiseContext(unsigned *pseed);
void FeepingCreature_DestroyNoiseContext(struct NoiseContext *nc);

#endif

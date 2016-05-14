//
//  GSTerrainGenerator.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/1/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainGenerator.h"
#import "GSNoise.h"
#import "GSBox.h"
#import "GSVectorUtils.h"


#define ARRAY_LEN(a) (sizeof(a)/sizeof(a[0]))
#define SWAP(x, y) do { typeof(x) temp##x##y = x; x = y; y = temp##x##y; } while (0)


struct GSPostProcessingRule
{
    /* Diagram shows the 9 voxel types at and around the block which matches this replacement rule.
     * So, if all surrounding voxel types match the diagram then this rule applies to that block.
     *
     * ' ' --> "Don't Care." The voxel type doesn't matter for this position.
     * '.' --> VOXEL_TYPE_EMPTY
     * '#' --> VOXEL_TYPE_CUBE
     * 'r' --> VOXEL_TYPE_RAMP
     *
     * North is at the top of the diagram.
     */
    char diagram[9];
    
    /* This voxel replaces the original one in th chunk. */
    GSVoxel replacement;
};

struct GSPostProcessingRuleSet
{
    size_t count;
    struct GSPostProcessingRule *rules;
    
    /* The rules only apply to empty blocks placed on top of blocks of the type specified by `appliesAboveBlockType'. */
    GSVoxelType appliesAboveBlockType;
    
    /* If YES then search from the bottom of the chunk to the top, on the undersides of ledges and stuff. */
    BOOL upsideDown;
};

static struct GSPostProcessingRule replacementRulesA[] =
{
    // Ramp pieces
    {
        " # "
        "..."
        " . ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_NORTH,
            .type = VOXEL_TYPE_RAMP
        }
    },
    {
        " . "
        "..#"
        " . ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_EAST,
            .type = VOXEL_TYPE_RAMP
        }
    },
    {
        " . "
        "..."
        " # ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_SOUTH,
            .type = VOXEL_TYPE_RAMP
        }
    },
    {
        " . "
        "#.."
        " . ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_WEST,
            .type = VOXEL_TYPE_RAMP
        }
    },
    
    // Inside corner pieces
    {
        "## "
        "#.."
        " . ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_NORTH,
            .type = VOXEL_TYPE_CORNER_INSIDE
        }
    },
    {
        " ##"
        "..#"
        " . ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_EAST,
            .type = VOXEL_TYPE_CORNER_INSIDE
        }
    },
    {
        " . "
        "..#"
        " ##",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_SOUTH,
            .type = VOXEL_TYPE_CORNER_INSIDE
        }
    },
    {
        " . "
        "#.."
        "## ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_WEST,
            .type = VOXEL_TYPE_CORNER_INSIDE
        }
    },
    
    // Outside corner pieces
    {
        "#.."
        ".. "
        ".  ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_NORTH,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        "..#"
        " .."
        "  .",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_EAST,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        "  ."
        " .."
        "..#",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_SOUTH,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        ".  "
        ".. "
        "#..",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_WEST,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
};

static struct GSPostProcessingRule replacementRulesB[] =
{
    {
        " r "
        "r. "
        "   ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_NORTH,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        " r "
        " .r"
        "   ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_EAST,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        "   "
        " .r"
        " r ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_SOUTH,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        "   "
        "r. "
        " r ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_WEST,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    
    
    {
        " # "
        "r. "
        "   ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_NORTH,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        " # "
        " .r"
        "   ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_EAST,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        "   "
        " .r"
        " # ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_SOUTH,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        "   "
        "r. "
        " # ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_WEST,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    
    
    {
        " r "
        "#. "
        "   ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_NORTH,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        " r "
        " .#"
        "   ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_EAST,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        "   "
        " .#"
        " r ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_SOUTH,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
    {
        "   "
        "#. "
        " r ",
        {
            .opaque = NO,
            .dir = VOXEL_DIR_WEST,
            .type = VOXEL_TYPE_CORNER_OUTSIDE
        }
    },
};

static struct GSPostProcessingRuleSet replacementRuleSets[] =
{
    {
        .count = ARRAY_LEN(replacementRulesA),
        .rules = replacementRulesA,
        .appliesAboveBlockType = VOXEL_TYPE_CUBE,
        .upsideDown = NO
    },
    {
        .count = ARRAY_LEN(replacementRulesB),
        .rules = replacementRulesB,
        .appliesAboveBlockType = VOXEL_TYPE_CORNER_INSIDE,
        .upsideDown = NO
    },
    {
        .count = ARRAY_LEN(replacementRulesA),
        .rules = replacementRulesA,
        .appliesAboveBlockType = VOXEL_TYPE_CUBE,
        .upsideDown = YES
    },
    {
        .count = ARRAY_LEN(replacementRulesB),
        .rules = replacementRulesB,
        .appliesAboveBlockType = VOXEL_TYPE_CORNER_INSIDE,
        .upsideDown = YES
    },
};


static BOOL typeMatchesCharacter(GSVoxelType type, char c);
static BOOL cellPositionMatchesRule(struct GSPostProcessingRule * _Nonnull rule, vector_long3 clp,
                                    GSVoxel *voxels, GSIntAABB * _Nonnull box);
static struct GSPostProcessingRule * _Nullable findRuleForCellPosition(size_t numRules,
                                                                       struct GSPostProcessingRule * _Nonnull rules,
                                                                       vector_long3 clp,
                                                                       GSVoxel * _Nonnull voxels,
                                                                       GSIntAABB * _Nonnull box);
static void postProcessingInnerLoop(GSIntAABB * _Nonnull box,
                                    vector_long3 p,
                                    GSVoxel * _Nonnull voxelsIn,
                                    GSVoxel * _Nonnull voxelsOut,
                                    struct GSPostProcessingRuleSet * _Nonnull ruleSet,
                                    GSVoxelType * _Nonnull prevType_p);
static void postProcessVoxels(struct GSPostProcessingRuleSet * _Nonnull ruleSet,
                              GSVoxel * _Nonnull voxelsIn,
                              GSVoxel * _Nonnull voxelsOut,
                              GSIntAABB * _Nonnull box);
static float groundGradient(float terrainHeight, vector_float3 p);
static void generateTerrainVoxel(GSNoise * _Nonnull noiseSource0, GSNoise * _Nonnull noiseSource1,
                                 float terrainHeight, vector_float3 p, GSVoxel * _Nonnull outVoxel);

@implementation GSTerrainGenerator
{
    GSNoise *_noiseSource0;
    GSNoise *_noiseSource1;
}

- (nonnull instancetype)init
{
    @throw nil;
}

- (nonnull instancetype)initWithRandomSeed:(NSInteger)seed
{
    if (self = [super init]) {
        _noiseSource0 = [[GSNoise alloc] initWithSeed:seed];
        _noiseSource1 = [[GSNoise alloc] initWithSeed:seed+1];
    }
    return self;
}

- (void)generateWithDestination:(nonnull GSVoxel *)voxels
                          count:(NSUInteger)count
                         region:(nonnull GSIntAABB *)box
                  offsetToWorld:(vector_float3)offsetToWorld
{
    NSParameterAssert(voxels);
    NSParameterAssert(box);
    
    const static float terrainHeight = 40.0f;
    vector_long3 clp;
    
    // First, generate voxels for a region of terrain.
    FOR_BOX(clp, *box)
    {
        vector_float3 worldPosition = vector_make(clp.x, clp.y, clp.z) + offsetToWorld;
        GSVoxel *voxel = &voxels[INDEX_BOX(clp, *box)];
        generateTerrainVoxel(_noiseSource0, _noiseSource1, terrainHeight, worldPosition, voxel);
    }
    
    // Second, post-process the voxels to add ramps and slopes.
    
    _Static_assert(ARRAY_LEN(replacementRuleSets)>0, "Must have at least one set of rules in replacementRuleSets.");
    
    GSVoxel *temp1 = malloc(count * sizeof(GSVoxel));
    if(!temp1) {
        [NSException raise:NSMallocException format:@"Out of memory allocating temp1."];
    }
    
    GSVoxel *temp2 = malloc(count * sizeof(GSVoxel));
    if(!temp2) {
        [NSException raise:NSMallocException format:@"Out of memory allocating temp2."];
    }
    
    postProcessVoxels(&replacementRuleSets[0], voxels, temp1, box);
    
    for(size_t i=1; i<ARRAY_LEN(replacementRuleSets); ++i)
    {
        postProcessVoxels(&replacementRuleSets[i], temp1, temp2, box);
        SWAP(temp1, temp2);
    }
    
    memcpy(voxels, temp1, count * sizeof(GSVoxel));
    
    free(temp1);
    free(temp2);
}

@end


static BOOL typeMatchesCharacter(GSVoxelType type, char c)
{
    // All voxel types match the space character.
    if(c == ' ') {
        return YES;
    }
    
    switch(c)
    {
        case '.':
            return type == VOXEL_TYPE_EMPTY;
            
        case '#':
            return type == VOXEL_TYPE_CUBE;
            
        case 'r':
            return (type == VOXEL_TYPE_RAMP) || (type == VOXEL_TYPE_CORNER_INSIDE);
    }
    
    return NO;
}

static BOOL cellPositionMatchesRule(struct GSPostProcessingRule * _Nonnull rule, vector_long3 clp,
                                    GSVoxel * _Nonnull voxels, GSIntAABB * _Nonnull box)
{
    assert(rule);
    assert(box);
    assert(clp.x >= box->mins.x && clp.x < box->maxs.x);
    assert(clp.y >= box->mins.y && clp.y < box->maxs.y);
    assert(clp.z >= box->mins.z && clp.z < box->maxs.z);
    
    for(long z=-1; z<=1; ++z)
    {
        for(long x=-1; x<=1; ++x)
        {
            if(x==0 && z==0) { // (0,0) refers to the target block, so the value in the diagram doesn't matter.
                continue;
            }

            vector_long3 p = { x+clp.x, clp.y, z+clp.z };
            GSVoxelType type = voxels[INDEX_BOX(p, *box)].type;
            long idx = 3*(-z+1) + (x+1);
            assert(idx >= 0 && idx < 9);
            char c = rule->diagram[idx];
            
            if(!typeMatchesCharacter(type, c)) {
                return NO;
            }
        }
    }
    
    return YES;
}

static struct GSPostProcessingRule * _Nullable findRuleForCellPosition(size_t numRules,
                                                                       struct GSPostProcessingRule * _Nonnull rules,
                                                                       vector_long3 clp,
                                                                       GSVoxel * _Nonnull voxels,
                                                                       GSIntAABB * _Nonnull box)
{
    assert(rules);
    assert(box);
    
    for(size_t i=0; i<numRules; ++i)
    {
        if(cellPositionMatchesRule(&rules[i], clp, voxels, box)) {
            return &rules[i];
        }
    }
    
    return NULL;
}

static void postProcessingInnerLoop(GSIntAABB * _Nonnull box, vector_long3 p,
                                    GSVoxel * _Nonnull voxelsIn, GSVoxel * _Nonnull voxelsOut,
                                    struct GSPostProcessingRuleSet * _Nonnull ruleSet,
                                    GSVoxelType * _Nonnull prevType_p)
{
    assert(box);
    assert(voxelsIn);
    assert(voxelsOut);
    assert(ruleSet);
    assert(prevType_p);
    
    const size_t idx = INDEX_BOX(p, *box);
    GSVoxel *voxel = &voxelsIn[idx];
    GSVoxelType prevType = *prevType_p;
    
    if(voxel->type == VOXEL_TYPE_EMPTY && (prevType == ruleSet->appliesAboveBlockType)) {
        // Find and apply the first post-processing rule which matches this position.
        struct GSPostProcessingRule *rule = findRuleForCellPosition(ruleSet->count, ruleSet->rules, p, voxelsIn, box);
        if(rule) {
            GSVoxel replacement = rule->replacement;
            replacement.tex = voxel->tex;
            replacement.outside = voxel->outside;
            replacement.exposedToAirOnTop = !ruleSet->upsideDown;
            replacement.upsideDown = ruleSet->upsideDown;
            voxelsOut[idx] = replacement;
        }
    }
    
    *prevType_p = voxel->type;
}

static void postProcessVoxels(struct GSPostProcessingRuleSet * _Nonnull ruleSet,
                              GSVoxel * _Nonnull voxelsIn, GSVoxel * _Nonnull voxelsOut,
                              GSIntAABB * _Nonnull box)
{
    assert(ruleSet);
    assert(voxelsIn);
    assert(voxelsOut);
    assert(box);
    
    vector_long3 p = {0};
    
    // Copy all voxels directly and then, below, replace a few according to the processing rules.
    const size_t numVoxels = (box->maxs.x-box->mins.x) * (box->maxs.y-box->mins.y) * (box->maxs.z-box->mins.z);
    memcpy(voxelsOut, voxelsIn, numVoxels * sizeof(GSVoxel));
    
    vector_long3 inset = { 1, 1, 1};
    GSIntAABB insetBox = { .mins = box->mins + inset, .maxs = box->maxs - inset };
    
    FOR_Y_COLUMN_IN_BOX(p, insetBox)
    {
        if(ruleSet->upsideDown) {
            // Find a voxel which is empty and is directly below a cube voxel.
            p.y = CHUNK_SIZE_Y-1;
            GSVoxelType prevType = voxelsIn[INDEX_BOX(p, *box)].type;
            for(p.y = CHUNK_SIZE_Y-2; p.y >= 0; --p.y)
            {
                postProcessingInnerLoop(box, p, voxelsIn, voxelsOut, ruleSet, &prevType);
            }
        } else {
            // Find a voxel which is empty and is directly above a cube voxel.
            p.y = 0;
            GSVoxelType prevType = voxelsIn[INDEX_BOX(p, *box)].type;
            for(p.y = 1; p.y < CHUNK_SIZE_Y; ++p.y)
            {
                postProcessingInnerLoop(box, p, voxelsIn, voxelsOut, ruleSet, &prevType);
            }
        }
    }
}

// Return a value between -1 and +1 so that a line through the y-axis maps to a smooth gradient of values from -1 to +1.
static float groundGradient(float terrainHeight, vector_float3 p)
{
    const float y = p.y;
    
    if(y < 0.0) {
        return -1;
    } else if(y > terrainHeight) {
        return +1;
    } else {
        return 2.0*(y/terrainHeight) - 1.0;
    }
}

// Generates a voxel for the specified point in space. Returns that voxel in `outVoxel'.
static void generateTerrainVoxel(GSNoise * _Nonnull noiseSource0, GSNoise * _Nonnull noiseSource1,
                                 float terrainHeight, vector_float3 p, GSVoxel * _Nonnull outVoxel)
{
    BOOL groundLayer = NO;
    BOOL floatingMountain = NO;
    
    assert(outVoxel);
    
    // Normal rolling hills
    {
        const float freqScale = 0.025;
        float n = [noiseSource0 noiseAtPointWithFourOctaves:(p * freqScale)];
        float turbScaleX = 2.0;
        float turbScaleY = terrainHeight / 2.0;
        float yFreq = turbScaleX * ((n+1) / 2.0);
        float t = turbScaleY * [noiseSource1 noiseAtPoint:vector_make(p.x*freqScale, p.y*yFreq*freqScale, p.z*freqScale)];
        groundLayer = groundGradient(terrainHeight, vector_make(p.x, p.y + t, p.z)) <= 0;
    }
    
    // Giant floating mountain
    {
        /* The floating mountain is generated by starting with a sphere and applying turbulence to the surface.
         * The upper hemisphere is also squashed to make the top flatter.
         */
        
        vector_float3 mountainCenter = vector_make(50, 50, 80);
        vector_float3 toMountainCenter = mountainCenter - p;
        float distance = vector_length(toMountainCenter);
        float radius = 30.0;
        
        // Apply turbulence to the surface of the mountain.
        float freqScale = 0.70;
        float turbScale = 15.0;
        
        // Avoid generating noise when too far away from the center to matter.
        if(distance > 2.0*radius) {
            floatingMountain = NO;
        } else {
            // Convert the point into spherical coordinates relative to the center of the mountain.
            float azimuthalAngle = acosf(toMountainCenter.z / distance);
            float polarAngle = atan2f(toMountainCenter.y, toMountainCenter.x);
            
            float t = turbScale * [noiseSource0 noiseAtPointWithFourOctaves:vector_make(azimuthalAngle * freqScale,
                                                                                        polarAngle * freqScale,
                                                                                        0.0)];
            
            // Flatten the top.
            if(p.y > mountainCenter.y) {
                radius -= (p.y - mountainCenter.y) * 3;
            }
            
            floatingMountain = (distance+t) < radius;
        }
    }
    
    outVoxel->outside = NO; // calculated later
    outVoxel->torch = NO;
    outVoxel->exposedToAirOnTop = NO; // calculated later
    outVoxel->opaque = groundLayer || floatingMountain;
    outVoxel->upsideDown = NO; // calculated later
    outVoxel->dir = VOXEL_DIR_NORTH;
    outVoxel->type = (groundLayer || floatingMountain) ? VOXEL_TYPE_CUBE : VOXEL_TYPE_EMPTY;
    outVoxel->tex = VOXEL_TEX_GRASS;
}
//
//  GSTerrain.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSIntegerVector3.h"
#import "Voxel.h"
#import "GSNoise.h"
#import "GSTerrainCursor.h"
#import "GSChunkStore.h"
#import "GSTextureArray.h"
#import "GSShader.h"
#import "GSCamera.h"
#import "GSTerrain.h"

#define ARRAY_LEN(a) (sizeof(a)/sizeof(a[0]))
#define SWAP(x, y) do { typeof(x) temp##x##y = x; x = y; y = temp##x##y; } while (0)


struct PostProcessingRule
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
    voxel_t replacement;
};

struct PostProcessingRuleSet
{
    size_t count;
    struct PostProcessingRule *rules;

    /* The rules only apply to empty blocks placed on top of blocks of the type specified by `appliesAboveBlockType'. */
    voxel_type_t appliesAboveBlockType;

    /* If YES then search from the bottom of the chunk to the top, on the undersides of ledges and stuff. */
    BOOL upsideDown;
};

static struct PostProcessingRule replacementRulesA[] =
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

static struct PostProcessingRule replacementRulesB[] =
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

static struct PostProcessingRuleSet replacementRuleSets[] =
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


static BOOL typeMatchesCharacter(voxel_type_t type, char c);
static BOOL cellPositionMatchesRule(struct PostProcessingRule *rule, GSIntegerVector3 clp,
                                    voxel_t *voxels, GSIntegerVector3 minP, GSIntegerVector3 maxP);
static struct PostProcessingRule * findRuleForCellPosition(size_t numRules, struct PostProcessingRule *rules,
                                                           GSIntegerVector3 clp,
                                                           voxel_t *voxels, GSIntegerVector3 minP, GSIntegerVector3 maxP);
static void postProcessingInnerLoop(GSIntegerVector3 maxP, GSIntegerVector3 minP, GSIntegerVector3 p,
                                    voxel_t *voxelsIn, voxel_t *voxelsOut,
                                    struct PostProcessingRuleSet *ruleSet, voxel_type_t *prevType_p);
static void postProcessVoxels(struct PostProcessingRuleSet *ruleSet,
                              voxel_t *voxelsIn, voxel_t *voxelsOut,
                              GSIntegerVector3 minP, GSIntegerVector3 maxP);
static float groundGradient(float terrainHeight, GLKVector3 p);
static void generateTerrainVoxel(NSUInteger seed, float terrainHeight, GLKVector3 p, voxel_t *outVoxel);
int checkGLErrors(void); // TODO: find a new home for checkGLErrors()


@implementation GSTerrain
{
    GSCamera *_camera;
    GSTextureArray *_textureArray;
    GSChunkStore *_chunkStore;
    GSTerrainCursor *_cursor;
    float _maxPlaceDistance;
}

- (NSString *)newShaderSourceStringFromFileAt:(NSString *)path
{
    NSError *error;
    NSString *str = [[NSString alloc] initWithContentsOfFile:path
                                                    encoding:NSMacOSRomanStringEncoding
                                                       error:&error];
    if (!str) {
        NSLog(@"Error reading file at %@: %@", path, [error localizedFailureReason]);
        return @"";
    }
    
    return str;
}

- (id)initWithSeed:(NSUInteger)seed
            camera:(GSCamera *)cam
         glContext:(NSOpenGLContext *)context
{
    self = [super init];
    if(self) {
        _camera = cam;
        
        assert(checkGLErrors() == 0);
        
        NSString *vertFn = [[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"] pathForResource:@"shader.vert" ofType:@"txt"];
        NSString *fragFn = [[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"] pathForResource:@"shader.frag" ofType:@"txt"];
        
        NSString *vertSrc = [self newShaderSourceStringFromFileAt:vertFn];
        NSString *fragSrc = [self newShaderSourceStringFromFileAt:fragFn];
        
        GSShader *terrainShader = [[GSShader alloc] initWithVertexShaderSource:vertSrc fragmentShaderSource:fragSrc];
        
        [terrainShader bind];
        [terrainShader bindUniformWithNSString:@"tex" val:0]; // texture unit 0
        
        assert(checkGLErrors() == 0);
        
        _textureArray = [[GSTextureArray alloc] initWithImagePath:[[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"]
                                                                  pathForResource:@"terrain"
                                                                  ofType:@"png"]
                                                     numTextures:4];

        terrain_generator_t generator = ^(GLKVector3 a, voxel_t *voxel) {
            const float terrainHeight = 40.0f;
            generateTerrainVoxel(seed, terrainHeight, a, voxel);
        };

        terrain_post_processor_t postProcessor = ^(size_t count, voxel_t *voxels, GSIntegerVector3 minP, GSIntegerVector3 maxP) {
            _Static_assert(ARRAY_LEN(replacementRuleSets)>0, "Must have at least one set of rules in replacementRuleSets.");

            voxel_t *temp1 = malloc(count * sizeof(voxel_t));
            if(!temp1) {
                [NSException raise:@"Out of Memory" format:@"Out of memory allocating temp1."];
            }

            voxel_t *temp2 = malloc(count * sizeof(voxel_t));
            if(!temp2) {
                [NSException raise:@"Out of Memory" format:@"Out of memory allocating temp2."];
            }

            postProcessVoxels(&replacementRuleSets[0], voxels, temp1, minP, maxP);

            for(size_t i=1; i<ARRAY_LEN(replacementRuleSets); ++i)
            {
                postProcessVoxels(&replacementRuleSets[i], temp1, temp2, minP, maxP);
                SWAP(temp1, temp2);
            }

            memcpy(voxels, temp1, count * sizeof(voxel_t));

            free(temp1);
            free(temp2);
        };
        
        _chunkStore = [[GSChunkStore alloc] initWithSeed:seed
                                                 camera:cam
                                            terrainShader:terrainShader
                                                glContext:context
                                                generator:generator
                                            postProcessor:postProcessor];
        
        _cursor = [[GSTerrainCursor alloc] init];
        
        _maxPlaceDistance = 6.0; // XXX: make this configurable
    }
    return self;
}

- (void)draw
{
    static const float edgeOffset = 1e-4;
    glDepthRange(edgeOffset, 1.0); // Use glDepthRange so the block cursor is properly offset from the block itself.
    [_textureArray bind];
    [_chunkStore drawActiveChunks];
    [_textureArray unbind];
    [_cursor drawWithEdgeOffset:edgeOffset];
    glDepthRange(0.0, 1.0);
}

- (void)updateWithDeltaTime:(float)dt
        cameraModifiedFlags:(unsigned)cameraModifiedFlags
{
    //Calculate the cursor position.
    if(cameraModifiedFlags) {
        [self recalcCursorPosition];
    }
    
    [_chunkStore updateWithCameraModifiedFlags:cameraModifiedFlags];
}

- (void)testPurge
{
    [_chunkStore purge];
}

- (void)placeBlockUnderCrosshairs
{
    if(_cursor.cursorIsActive) {
        voxel_t block;
        
        bzero(&block, sizeof(voxel_t));
        block.opaque = YES;
        block.dir = VOXEL_DIR_NORTH;
        block.type = VOXEL_TYPE_CUBE;
        
        [_chunkStore placeBlockAtPoint:_cursor.cursorPlacePos block:block];
        [self recalcCursorPosition];
    }
}

- (void)removeBlockUnderCrosshairs
{
    if(_cursor.cursorIsActive) {
        voxel_t block;
        
        bzero(&block, sizeof(voxel_t));
        block.dir = VOXEL_DIR_NORTH;
        block.type = VOXEL_TYPE_EMPTY;
        
        [_chunkStore placeBlockAtPoint:_cursor.cursorPos block:block];
        [self recalcCursorPosition];
    }
}

- (void)recalcCursorPosition
{
    GSRay ray = GSRay_Make(_camera.cameraEye, GLKQuaternionRotateVector3(_camera.cameraRot, GLKVector3Make(0, 0, -1)));
    __block BOOL cursorIsActive = NO;
    __block GLKVector3 prev = ray.origin;
    __block GLKVector3 cursorPos;
    
    [_chunkStore enumerateVoxelsOnRay:ray maxDepth:_maxPlaceDistance withBlock:^(GLKVector3 p, BOOL *stop, BOOL *fail) {
        voxel_t voxel;

        if(![_chunkStore tryToGetVoxelAtPoint:p voxel:&voxel]) {
            *fail = YES; // Stops enumerations with un-successful condition
        }
        
        if(voxel.type != VOXEL_TYPE_EMPTY) {
            cursorIsActive = YES;
            cursorPos = p;
            *stop = YES; // Stops enumeration with successful condition.
        } else {
            prev = p;
        }
    }];

    _cursor.cursorIsActive = cursorIsActive;
    _cursor.cursorPos = cursorPos;
    _cursor.cursorPlacePos = prev;
}

- (void)shutdown
{
    [_chunkStore shutdown];
    _chunkStore = nil;
}

@end

static BOOL typeMatchesCharacter(voxel_type_t type, char c)
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

static BOOL cellPositionMatchesRule(struct PostProcessingRule *rule, GSIntegerVector3 clp,
                                    voxel_t *voxels, GSIntegerVector3 minP, GSIntegerVector3 maxP)
{
    assert(rule);
    assert(clp.x >= 0 && clp.x < CHUNK_SIZE_X);
    assert(clp.y >= 0 && clp.y < CHUNK_SIZE_Y);
    assert(clp.z >= 0 && clp.z < CHUNK_SIZE_Z);

    for(ssize_t x=-1; x<=1; ++x)
    {
        for(ssize_t z=-1; z<=1; ++z)
        {
            if(x==0 && z==0) { // (0,0) refers to the target block, so the value in the diagram doesn't matter.
                continue;
            }

            GSIntegerVector3 p = GSIntegerVector3_Make(x+clp.x, clp.y, z+clp.z);
            voxel_type_t type = voxels[INDEX_BOX(p, minP, maxP)].type;
            ssize_t idx = 3*(-z+1) + (x+1);
            assert(idx >= 0 && idx < 9);
            char c = rule->diagram[idx];

            if(!typeMatchesCharacter(type, c)) {
                return NO;
            }
        }
    }

    return YES;
}

static struct PostProcessingRule * findRuleForCellPosition(size_t numRules, struct PostProcessingRule *rules,
                                                           GSIntegerVector3 clp,
                                                           voxel_t *voxels, GSIntegerVector3 minP, GSIntegerVector3 maxP)
{
    assert(rules);

    for(size_t i=0; i<numRules; ++i)
    {
        if(cellPositionMatchesRule(&rules[i], clp, voxels, minP, maxP)) {
            return &rules[i];
        }
    }

    return NULL;
}

static void postProcessingInnerLoop(GSIntegerVector3 maxP, GSIntegerVector3 minP, GSIntegerVector3 p,
                                    voxel_t *voxelsIn, voxel_t *voxelsOut,
                                    struct PostProcessingRuleSet *ruleSet, voxel_type_t *prevType_p)
{
    assert(voxelsIn);
    assert(voxelsOut);
    assert(ruleSet);
    assert(prevType_p);

    const size_t idx = INDEX_BOX(p, minP, maxP);
    voxel_t *voxel = &voxelsIn[idx];

    if(voxel->type == VOXEL_TYPE_EMPTY && *prevType_p == ruleSet->appliesAboveBlockType) {
        // Find and apply the first post-processing rule which matches this position.
        struct PostProcessingRule *rule = findRuleForCellPosition(ruleSet->count, ruleSet->rules, p, voxelsIn, minP, maxP);
        if(rule) {
            voxel_t replacement = rule->replacement;
            replacement.tex = voxel->tex;
            replacement.outside = voxel->outside;
            replacement.exposedToAirOnTop = !ruleSet->upsideDown;
            replacement.upsideDown = ruleSet->upsideDown;
            voxelsOut[idx] = replacement;
        }
    }

    *prevType_p = voxel->type;
}

static void postProcessVoxels(struct PostProcessingRuleSet *ruleSet,
                              voxel_t *voxelsIn, voxel_t *voxelsOut,
                              GSIntegerVector3 minP, GSIntegerVector3 maxP)
{
    assert(ruleSet);
    assert(voxelsIn);
    assert(voxelsOut);

    GSIntegerVector3 p = {0};

    // Copy all voxels directly and then, below, replace a few according to the processing rules.
    const size_t numVoxels = (maxP.x-minP.x) * (maxP.y-minP.y) * (maxP.z-minP.z);
    memcpy(voxelsOut, voxelsIn, numVoxels * sizeof(voxel_t));

    FOR_Y_COLUMN_IN_BOX(p, ivecZero, chunkSize)
    {
        if(ruleSet->upsideDown) {
            // Find a voxel which is empty and is directly below a cube voxel.
            p.y = CHUNK_SIZE_Y-1;
            voxel_type_t prevType = voxelsIn[INDEX_BOX(p, minP, maxP)].type;
            for(p.y = CHUNK_SIZE_Y-2; p.y >= 0; --p.y)
            {
                postProcessingInnerLoop(maxP, minP, p, voxelsIn, voxelsOut, ruleSet, &prevType);
            }
        } else {
            // Find a voxel which is empty and is directly above a cube voxel.
            p.y = 0;
            voxel_type_t prevType = voxelsIn[INDEX_BOX(p, minP, maxP)].type;
            for(p.y = 1; p.y < CHUNK_SIZE_Y; ++p.y)
            {
                postProcessingInnerLoop(maxP, minP, p, voxelsIn, voxelsOut, ruleSet, &prevType);
            }
        }
    }
}

// Return a value between -1 and +1 so that a line through the y-axis maps to a smooth gradient of values from -1 to +1.
static float groundGradient(float terrainHeight, GLKVector3 p)
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
static void generateTerrainVoxel(NSUInteger seed, float terrainHeight, GLKVector3 p, voxel_t *outVoxel)
{
    static dispatch_once_t onceToken;
    static GSNoise *noiseSource0;
    static GSNoise *noiseSource1;

    BOOL groundLayer = NO;
    BOOL floatingMountain = NO;

    assert(outVoxel);

    dispatch_once(&onceToken, ^{
        noiseSource0 = [[GSNoise alloc] initWithSeed:seed];
        noiseSource1 = [[GSNoise alloc] initWithSeed:seed+1];
    });

    // Normal rolling hills
    {
        const float freqScale = 0.025;
        float n = [noiseSource0 noiseAtPointWithFourOctaves:GLKVector3MultiplyScalar(p, freqScale)];
        float turbScaleX = 2.0;
        float turbScaleY = terrainHeight / 2.0;
        float yFreq = turbScaleX * ((n+1) / 2.0);
        float t = turbScaleY * [noiseSource1 noiseAtPoint:GLKVector3Make(p.x*freqScale, p.y*yFreq*freqScale, p.z*freqScale)];
        groundLayer = groundGradient(terrainHeight, GLKVector3Make(p.x, p.y + t, p.z)) <= 0;
    }

    // Giant floating mountain
    {
        /* The floating mountain is generated by starting with a sphere and applying turbulence to the surface.
         * The upper hemisphere is also squashed to make the top flatter.
         */

        GLKVector3 mountainCenter = GLKVector3Make(50, 50, 80);
        GLKVector3 toMountainCenter = GLKVector3Subtract(mountainCenter, p);
        float distance = GLKVector3Length(toMountainCenter);
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

            float t = turbScale * [noiseSource0 noiseAtPointWithFourOctaves:GLKVector3Make(azimuthalAngle * freqScale,
                                                                                           polarAngle * freqScale,
                                                                                           0.0)];

            // Flatten the top.
            if(p.y > mountainCenter.y) {
                radius -= (p.y - mountainCenter.y) * 3;
            }

            floatingMountain = (distance+t) < radius;
        }
    }

    outVoxel->dir = VOXEL_DIR_NORTH;
    outVoxel->outside = NO; // calculated later
    outVoxel->exposedToAirOnTop = NO; // calculated later
    outVoxel->opaque = groundLayer || floatingMountain;
    outVoxel->tex = VOXEL_TEX_GRASS;
    outVoxel->type = (groundLayer || floatingMountain) ? VOXEL_TYPE_CUBE : VOXEL_TYPE_EMPTY;
}
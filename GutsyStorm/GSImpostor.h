//
//  GSImpostor.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSRenderTexture.h"
#import "GSCamera.h"
#import "GSAABB.h"
#import "GSMatrix4.h"


@interface GSImpostor : NSObject
{
	GSRenderTexture *renderTexture;
	
	GSVector3 verts[4];
	GSVector3 texCoords[4]; // z is ignored
	GSVector3 center;
	
	GSVector3 cameraVec;
	GSCamera *camera;
	
	GSAABB *bounds; // the volume of the object being represented
	
	// Pixels that the object takes up within the render texture.
	float pixelsLeft;
	float pixelsRight;
	float pixelsBottom;
	float pixelsTop;
	
	BOOL shouldForceImpostorUpdate;
}

- (id)initWithCamera:(GSCamera *)camera bounds:(GSAABB *)bounds;
- (void)realignToCamera;
- (void)startUpdateImposter; // Returns NO if there's no point in updating now, e.g. camera transformation puts it off screen.
- (void)finishUpdateImposter;
- (void)draw;
- (BOOL)doesImposterNeedUpdate;
- (void)setNeedsImpostorUpdate:(BOOL)shouldForceImpostorUpdate;

@end

//
//  GSGridEdit.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/10/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKMath.h>

@interface GSGridEdit : NSObject

@property (nonatomic, strong) id originalObject;
@property (nonatomic, strong) id modifiedObject;
@property (nonatomic, assign) GLKVector3 pos;

- (instancetype)initWithOriginalItem:(id)item
                        modifiedItem:(id)replacement
                                 pos:(GLKVector3)p;

@end

//
//  GSMutableBuffer.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/23/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSTerrainBuffer.h"

@interface GSMutableBuffer : GSTerrainBuffer

+ (nonnull instancetype)newMutableBufferWithBuffer:(nonnull GSTerrainBuffer *)buffer;

- (nonnull GSTerrainBufferElement *)mutableData;

@end

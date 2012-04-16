//
//  GSVertex.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSVertex.h"

@implementation GSVertex

@synthesize position;
@synthesize normal;
@synthesize texCoord;


- (id)initWithPosition:(GSBoxedVector *)_position
				normal:(GSBoxedVector *)_normal
			  texCoord:(GSBoxedVector *)_texCoord
{
	self = [super init];
    if (self) {
        // Initialization code here.
        position = _position;
        normal = _normal;
        texCoord = _texCoord;
    }
    
    return self;
}


- (BOOL)isEqual:(id)other
{
    if(other == self) {
        return YES;
	}
	
    if(!other || ![other isKindOfClass:[self class]]) {
        return NO;
	}
	
    return [self isEqualToVertex:other];
}


- (BOOL)isEqualToVertex:(GSVertex *)vertex
{
    if(self == vertex) {
        return YES;
	}
	
    return [position isEqual:vertex.position] &&
		   [normal isEqual:vertex.normal] &&
	       [texCoord isEqual:vertex.texCoord];
}


- (NSUInteger)hash
{
	NSUInteger prime = 31;
	NSUInteger result = 1;
	
	result = prime * result + [position hash];
	result = prime * result + [normal hash];
	result = prime * result + [texCoord hash];
	
	return result;
	
}


- (NSString *)toString
{
	return [NSString stringWithFormat:@"position=%@ ; normal=%@ ; texCoord=%@",
			[position toString], [normal toString], [texCoord toString]];
}

@end

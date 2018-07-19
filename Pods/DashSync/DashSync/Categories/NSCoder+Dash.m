//
//  NSCoder+Dash.m
//  DashSync
//
//  Created by Sam Westrich on 5/19/18.
//

#import "NSCoder+Dash.h"
#import "IntTypes.h"
#import "NSData+Bitcoin.h"

@implementation NSCoder (Dash)

-(void)encodeUInt256:(UInt256)value forKey:(NSString*)string {
    [self encodeObject:[NSData dataWithUInt256:value] forKey:string];
}

-(UInt256)decodeUInt256ForKey:(NSString*)string {
    NSData * data = [self decodeObjectOfClass:[NSData class] forKey:string];
    UInt256 r = *(UInt256 *)data.bytes;
    return r;
}

@end

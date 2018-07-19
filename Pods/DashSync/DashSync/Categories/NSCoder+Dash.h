//
//  NSCoder+Dash.h
//  DashSync
//
//  Created by Sam Westrich on 5/19/18.
//

#import <Foundation/Foundation.h>
#import "IntTypes.h"

@interface NSCoder (Dash)

-(void)encodeUInt256:(UInt256)value forKey:(NSString*)string;
-(UInt256)decodeUInt256ForKey:(NSString*)string;

@end

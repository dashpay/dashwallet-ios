//
//  ZNWallet.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/12/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZNWallet : NSObject

@property (nonatomic, readonly) double balance;
@property (nonatomic, readonly) NSString *receiveAddress;

+ (ZNWallet *)singleton;

- (id)initWithSeed:(NSString *)seed;
- (NSString *)transactionFor:(double)amount to:(NSString *)address;

@end

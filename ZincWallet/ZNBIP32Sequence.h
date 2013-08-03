//
//  ZNBIP32Sequence.h
//  ZincWallet
//
//  Created by Administrator on 7/19/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZNKeySequence.h"

@interface ZNBIP32Sequence : NSObject<ZNKeySequence>

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed;
- (NSData *)publicKey:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey;
- (NSString *)privateKey:(NSUInteger)n internal:(BOOL)internal fromSeed:(NSData *)seed;
- (NSArray *)privateKeys:(NSArray *)n internal:(BOOL)internal fromSeed:(NSData *)seed;

- (NSString *)serializedPrivateMasterFromSeed:(NSData *)seed;
- (NSString *)serializedMasterPublicKey:(NSData *)masterPublicKey;

@end

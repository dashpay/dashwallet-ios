//
//  ZNElectrumSequence.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/27/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZNKeySequence.h"

#define ELECTRUM_SEED_LENGTH (128/8)
#define ELECTURM_GAP_LIMIT 10
#define ELECTURM_GAP_LIMIT_FOR_CHANGE 3 // this is hard coded in the electrum client

@interface ZNElectrumSequence : NSObject<ZNKeySequence>

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed;
- (NSData *)publicKey:(NSUInteger)n forChange:(BOOL)forChange masterPublicKey:(NSData *)masterPublicKey;

- (NSString *)privateKey:(NSUInteger)n forChange:(BOOL)forChange fromSeed:(NSData *)seed;
- (NSArray *)privateKeys:(NSArray *)n forChange:(BOOL)forChange fromSeed:(NSData *)seed;

@end

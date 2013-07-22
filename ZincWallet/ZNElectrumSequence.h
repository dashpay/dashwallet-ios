//
//  ZNElectrumSequence.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/27/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZNKeySequence.h"

#define ELECTRUM_SEED_LENGTH          (128/8)
#define ELECTURM_GAP_LIMIT            10
#define ELECTURM_GAP_LIMIT_FOR_CHANGE 3 // this is hard coded in the electrum client
#define ELECTRUM_WORD_LIST_RESOURCE   @"ElectrumSeedWords"

@interface ZNElectrumSequence : NSObject<ZNKeySequence>

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed;
- (NSData *)publicKey:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey;
- (NSString *)privateKey:(NSUInteger)n internal:(BOOL)internal fromSeed:(NSData *)seed;
- (NSArray *)privateKeys:(NSArray *)n internal:(BOOL)internal fromSeed:(NSData *)seed;

@end

//
//  ZNElectrumSequence.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/27/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZNKeySequence.h"

@interface ZNElectrumSequence : NSObject<ZNKeySequence>

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed;
- (NSData *)publicKey:(NSUInteger)n forChange:(BOOL)forChange masterPublicKey:(NSData *)masterPublicKey;

@end

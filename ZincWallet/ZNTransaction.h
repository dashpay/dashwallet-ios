//
//  ZNTransaction.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/16/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZNTransaction : NSObject

// inputHashes are expected to already be little endian
- (id)initWithInputHashes:(NSArray *)inputHashes inputIndexes:(NSArray *)inputIndexes
inputScripts:(NSArray *)inputScripts outputAddresses:(NSArray *)outputAddresses
andOutputAmounts:(NSArray *)outputAmounts;

- (BOOL)isSigned;

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys;

- (NSData *)toData;

- (NSString *)toHex;

@end

//
//  ZNTransaction.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/16/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZNTransaction : NSObject

- (id)initWithInputHashes:(NSArray *)inputHashes inputIndexes:(NSArray *)inputIndexes
  outputAddresses:(NSArray *)outputAddresses andOutputAmounts:(NSArray *)outputAmounts;

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys;

@end

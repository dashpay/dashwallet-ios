//
//  ZNElecturmMnemonic.h
//  ZincWallet
//
//  Created by Aaron Voisine on 7/19/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZNMnemonic.h"

#define ELECTRUM_WORD_LIST_RESOURCE   @"ElectrumSeedWords"

@interface ZNElecturmMnemonic : NSObject<ZNMnemonic>

+ (instancetype)mnemonicWithWords:(NSArray *)words;
+ (instancetype)mnemonicWithWordPlist:(NSString *)plist;

- (instancetype)initWithWords:(NSArray *)words;
- (instancetype)initWithWordPlist:(NSString *)plist;

- (NSString *)encodePhrase:(NSData *)data;
- (NSData *)decodePhrase:(NSString *)phrase;

@end

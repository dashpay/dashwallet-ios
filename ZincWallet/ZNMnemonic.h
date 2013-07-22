//
//  ZNMnemonic.h
//  ZincWallet
//
//  Created by Administrator on 7/19/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZNMnemonic : NSObject

+ (ZNMnemonic *)mnemonicWithWords:(NSArray *)words;
+ (ZNMnemonic *)mnemonicWithWordPlist:(NSString *)plist;

- (instancetype)initWithWords:(NSArray *)words;
- (instancetype)initWithWordPlist:(NSString *)plist;

- (NSString *)encodePhrase:(NSData *)data;
- (NSData *)decodePhrase:(NSString *)phrase;

@end

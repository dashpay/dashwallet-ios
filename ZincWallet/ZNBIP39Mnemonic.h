//
//  ZNBIP39Mnemonic.h
//  ZincWallet
//
//  Created by Aaron Voisine on 8/15/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZNMnemonic.h"

@interface ZNBIP39Mnemonic : NSObject<ZNMnemonic>

- (NSString *)encodePhrase:(NSData *)data;
- (NSData *)decodePhrase:(NSString *)phrase;

@end

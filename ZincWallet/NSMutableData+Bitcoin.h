//
//  NSMutableData+Bitcoin.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/20/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableData (Bitcoin)

- (void)appendUInt32:(uint32_t)i;
- (void)appendUInt64:(uint64_t)i;
- (void)appendVarInt:(uint64_t)i;
- (void)appendString:(NSString *)s;
- (void)appendHash:(NSData *)hash;
- (void)appendScriptPubKeyForHash:(NSData *)hash;
- (BOOL)appendScriptPubKeyForAddress:(NSString *)address;

@end

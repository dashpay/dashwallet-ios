//
//  NSString+Base58.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <Foundation/Foundation.h>

#define BITCOIN_TESTNET NO

#define BITCOIN_PUBKEY_ADDRESS 0
#define BITCOIN_SCRIPT_ADDRESS 5
#define BITCOIN_PUBKEY_ADDRESS_TEST 111
#define BITCOIN_SCRIPT_ADDRESS_TEST 196

CFAllocatorRef SecureAllocator();

@interface NSString (Base58)

+ (NSString *)base58WithData:(NSData *)d;
+ (NSString *)base58checkWithData:(NSData *)d;
+ (NSString *)hexWithData:(NSData *)d;

- (NSData *)base58ToData;
- (NSString *)hexToBase58;
- (NSString *)base58ToHex;

- (NSData *)base58checkToData;
- (NSString *)hexToBase58check;
- (NSString *)base58checkToHex;

- (NSData *)hexToData;

- (BOOL)isValidBitcoinAddress;

@end

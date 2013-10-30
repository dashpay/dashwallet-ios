//
//  NSString+Base58.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import <Foundation/Foundation.h>

#define BITCOIN_PUBKEY_ADDRESS      0
#define BITCOIN_SCRIPT_ADDRESS      5
#define BITCOIN_PUBKEY_ADDRESS_TEST 111
#define BITCOIN_SCRIPT_ADDRESS_TEST 196
#define BITCOIN_PRIVKEY             128
#define BITCOIN_PRIVKEY_TEST        239

CFAllocatorRef SecureAllocator();

@interface NSString (Base58)

+ (NSString *)base58WithData:(NSData *)d;
+ (NSString *)base58checkWithData:(NSData *)d;
+ (NSString *)hexWithData:(NSData *)d;
+ (NSString *)addressWithScript:(NSData *)script;

- (NSData *)base58ToData;
- (NSString *)hexToBase58;
- (NSString *)base58ToHex;

- (NSData *)base58checkToData;
- (NSString *)hexToBase58check;
- (NSString *)base58checkToHex;

- (NSData *)hexToData;

- (BOOL)isValidBitcoinAddress;
- (BOOL)isValidBitcoinPrivateKey;

@end

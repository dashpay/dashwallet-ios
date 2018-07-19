//
//  NSMutableData+Dash.h
//  DashSync
//
//  Created by Aaron Voisine on 5/20/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  Updated by Quantum Explorer on 05/11/18.
//  Copyright (c) 2018 Quantum Explorer <quantum@dash.org>
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

#import "IntTypes.h"

CF_IMPLICIT_BRIDGING_ENABLED

CFAllocatorRef SecureAllocator(void);

CF_IMPLICIT_BRIDGING_DISABLED

@class DSChain;

@interface NSMutableData (Dash)

+ (NSMutableData *)secureData;
+ (NSMutableData *)secureDataWithLength:(NSUInteger)length;
+ (NSMutableData *)secureDataWithCapacity:(NSUInteger)capacity;
+ (NSMutableData *)secureDataWithData:(NSData *)data;

+ (size_t)sizeOfVarInt:(uint64_t)i;

- (void)appendUInt8:(uint8_t)i;
- (void)appendUInt16:(uint16_t)i;
- (void)appendUInt32:(uint32_t)i;
- (void)appendUInt64:(uint64_t)i;
- (void)appendUInt128:(UInt128)i;
- (void)appendUInt160:(UInt160)i;
- (void)appendUInt256:(UInt256)i;
- (void)appendVarInt:(uint64_t)i;
- (void)appendString:(NSString *)s;

- (void)appendDevnetGenesisCoinbaseMessage:(NSString *)message;
- (void)appendCoinbaseMessage:(NSString *)message atHeight:(uint32_t)height;

- (void)appendBitcoinScriptPubKeyForAddress:(NSString *)address forChain:(DSChain*)chain;
- (void)appendScriptPubKeyForAddress:(NSString *)address forChain:(DSChain*)chain;
- (void)appendScriptPushData:(NSData *)d;

- (void)appendShapeshiftMemoForAddress:(NSString *)address;
- (void)appendProposalInfo:(NSData*)proposalInfo;

- (void)appendMessage:(NSData *)message type:(NSString *)type forChain:(DSChain*)chain;
- (void)appendNullPaddedString:(NSString *)s length:(NSUInteger)length;
- (void)appendNetAddress:(uint32_t)address port:(uint16_t)port services:(uint64_t)services;

@end

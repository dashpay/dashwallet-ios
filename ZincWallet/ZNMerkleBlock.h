//
//  ZNMerkleBlock.h
//  ZincWallet
//
//  Created by Aaron Voisine on 10/22/13.
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

@interface ZNMerkleBlock : NSObject

@property (nonatomic, readonly) NSData *blockHash;
@property (nonatomic, readonly) int32_t height;
@property (nonatomic, readonly) int32_t version;
@property (nonatomic, readonly) NSData *prevBlock;
@property (nonatomic, readonly) NSData *merkleRoot;
@property (nonatomic, readonly) NSTimeInterval timestamp;
@property (nonatomic, readonly) int32_t bits;
@property (nonatomic, readonly) int32_t nonce;
@property (nonatomic, readonly) int32_t totalTransactions;
@property (nonatomic, readonly) NSData *hashes;
@property (nonatomic, readonly) NSData *flags;

@property (nonatomic, readonly) NSArray *txHashes; // the matched tx hashes in the block
@property (nonatomic, readonly, getter = isValid) BOOL valid; // true if difficulty and merkle tree hashes are correct

+ (instancetype)blockWithMessage:(NSData *)message;

- (instancetype)initWithMessage:(NSData *)message;

// true if the given tx hash is included in the block
- (BOOL)containsTxHash:(NSData *)txHash;

@end

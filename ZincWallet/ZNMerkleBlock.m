//
//  ZNMerkleBlock.m
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

#import "ZNMerkleBlock.h"
#import "NSData+Bitcoin.h"
#import "NSData+Hash.h"
#import <openssl/bn.h>

#define MAX_TIME_DRIFT    (2*60*60)
#define MAX_PROOF_OF_WORK 0x1d00ffffu // highest value for difficulty target (higher values are less difficult)

// convert difficulty target format to bignum, as per: https://github.com/bitcoin/bitcoin/blob/master/src/bignum.h#L289
static void setCompact(BIGNUM *bn, uint32_t compact)
{
    uint32_t size = compact >> 24, word = compact & 0x007fffff;
    
    if (size > 3) {
        BN_set_word(bn, word);
        BN_lshift(bn, bn, 8*(size - 3));
    }
    else BN_set_word(bn, word >> 8*(3 - size));
    
    BN_set_negative(bn, (compact & 0x00800000) != 0);
}

// from https://en.bitcoin.it/wiki/Protocol_specification#Merkle_Trees
// Merkle trees are binary trees of hashes. Merkle trees in bitcoin use a double SHA-256, the SHA-256 hash of the
// SHA-256 hash of something. If, when forming a row in the tree (other than the root of the tree), it would have an odd
// number of elements, the final double-hash is duplicated to ensure that the row has an even number of hashes. First
// form the bottom row of the tree with the ordered double-SHA-256 hashes of the byte streams of the transactions in the
// block. Then the row above it consists of half that number of hashes. Each entry is the double-SHA-256 of the 64-byte
// concatenation of the corresponding two hashes below it in the tree. This procedure repeats recursively until we reach
// a row consisting of just a single double-hash. This is the merkle root of the tree.
//
// from https://en.bitcoin.it/wiki/BIP_0037#Partial_Merkle_branch_format
// The encoding works as follows: we traverse the tree in depth-first order, storing a bit for each traversed node,
// signifying whether the node is the parent of at least one matched leaf txid (or a matched txid itself). In case we
// are at the leaf level, or this bit is 0, its merkle node hash is stored, and its children are not explored further.
// Otherwise, no hash is stored, but we recurse into both (or the only) child branch. During decoding, the same
// depth-first traversal is performed, consuming bits and hashes as they written during encoding.
//
// example tree with three transactions, where only tx2 is matched by the bloom filter:
//
//     merkleRoot
//      /     \
//    m1       m2
//   /  \     /  \
// tx1  tx2 tx3  tx3
//
// flag bits: 00001011 [merkleRoot = 1, m1 = 1, tx1 = 0, tx2 = 1, m2 = 0, byte padding = 000]
// hashes: [tx1, tx2, m2]

@implementation ZNMerkleBlock

+ (instancetype)blockWithMessage:(NSData *)message
{
    return [[self alloc] initWithMessage:message];
}

- (instancetype)initWithMessage:(NSData *)message
{
    NSUInteger off = 0, l = 0, len = 0;
    
    if (! (self = [self init])) return nil;
    
    if (message.length < 80) return self;
    
    _blockHash = [[[message subdataWithRange:NSMakeRange(0, 80)] SHA256_2] reverse];
    _version = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _prevBlock = [message hashAtOffset:off];
    off += CC_SHA256_DIGEST_LENGTH;
    _merkleRoot = [message hashAtOffset:off];
    off += CC_SHA256_DIGEST_LENGTH;
    _timestamp = [message UInt32AtOffset:off] - NSTimeIntervalSince1970;
    off += sizeof(uint32_t);
    _bits = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _nonce = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _totalTransactions = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    len = [message varIntAtOffset:off length:&l]*CC_SHA256_DIGEST_LENGTH;
    off += l;
    _hashes = off + len > message.length ? nil : [message subdataWithRange:NSMakeRange(off, len)];
    off += len;
    _flags = [message dataAtOffset:off length:&l];
    
    return self;
}

// convert difficulty target bits to bignum, as per: https://github.com/bitcoin/bitcoin/blob/master/src/bignum.h#L289
- (BIGNUM)difficultyTarget
{
    uint32_t size = _bits >> 24, word = _bits & 0x007fffff;
    BIGNUM target;
    
    BN_init(&target);

    if (size > 3) {
        BN_set_word(&target, word);
        BN_lshift(&target, &target, 8*(size - 3));
    }
    else BN_set_word(&target, word >> 8*(3 - size));
    
    BN_set_negative(&target, (_bits & 0x00800000) != 0);
    
    return target;
}

- (BOOL)isValid
{
    __block NSMutableData *d = [NSMutableData data];
    BIGNUM target, maxTarget, hash;
    int hashIdx = 0, flagIdx = 0;
    NSData *merkleRoot =
        [self _walk:&hashIdx :&flagIdx :0 :^id (NSData *hash, BOOL flag) {
            return hash;
        } :^id (id left, id right) {
            [d setData:left];
            [d appendData:right ? right : left]; // if right branch is missing, duplicate left branch
            return [d SHA256_2];
        }];
    
    if (! [merkleRoot isEqual:_merkleRoot]) return NO; // merkle root check failed
    
    if (_timestamp > [NSDate timeIntervalSinceReferenceDate] + MAX_TIME_DRIFT) return NO; // timestamp too far in future
    
    // Check proof-of-work. This only checks if the block difficulty matches what is claimed in the header. It does not
    // check if the difficulty is correct for the block's height in the chain.
    BN_init(&target);
    BN_init(&maxTarget);
    BN_init(&hash);
    setCompact(&target, _bits);
    setCompact(&maxTarget, MAX_PROOF_OF_WORK);
    BN_bin2bn(_blockHash.bytes, CC_SHA256_DIGEST_LENGTH, &hash);
    
    if (BN_cmp(&target, BN_value_one()) < 0 || BN_cmp(&target, &maxTarget) > 0) return NO; // target out of range

    if (BN_cmp(&hash, &target) > 0) return NO; // block not as difficult as target (smaller values are more difficult)

    return YES;
}

- (BOOL)containsTxHash:(NSData *)txHash
{
    txHash = [txHash reverse];

    for (NSUInteger i = 0; i < _hashes.length/CC_SHA256_DIGEST_LENGTH; i += CC_SHA256_DIGEST_LENGTH) {
        if (! [txHash isEqual:[_hashes hashAtOffset:i]]) continue;
        return YES;
    }
    
    return NO;
}

// returns an array of the matched tx hashes
- (NSArray *)txHashes
{
    int hashIdx = 0, flagIdx = 0;
    NSArray *txHashes =
        [self _walk:&hashIdx :&flagIdx :0 :^id (NSData *hash, BOOL flag) {
            return (flag && hash) ? @[[hash reverse]] : @[];
        } :^id (id left, id right) {
            return [left arrayByAddingObjectsFromArray:right];
        }];
    
    return txHashes;
}

// recursively walks the merkle tree in depth first order, calling leaf(hash, flag) for each stored hash, and
// branch(left, right) with the result from each branch
- (id)_walk:(int *)hashIdx :(int *)flagIdx :(int)depth :(id (^)(NSData *, BOOL))leaf :(id (^)(id, id))branch
{
    if ((*flagIdx)/8 >= _flags.length || (*hashIdx + 1)*CC_SHA256_DIGEST_LENGTH > _hashes.length) return leaf(nil, NO);
    
    BOOL flag = (((uint8_t *)_flags.bytes)[*flagIdx/8] & (1 << (*flagIdx % 8)));
    
    (*flagIdx)++;
    
    if (! flag || depth == ceil(log2(_totalTransactions))) {
        NSData *hash = [_hashes hashAtOffset:(*hashIdx)*CC_SHA256_DIGEST_LENGTH];
        
        (*hashIdx)++;
        return leaf(hash, flag);
    }
    
    id left = [self _walk:hashIdx :flagIdx :depth + 1 :leaf :branch];
    id right = [self _walk:hashIdx :flagIdx :depth + 1 :leaf :branch];
    
    return branch(left, right);
}

@end

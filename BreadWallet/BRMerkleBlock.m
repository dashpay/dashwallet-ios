//
//  BRMerkleBlock.m
//  BreadWallet
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

#import "BRMerkleBlock.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Bitcoin.h"

#define MAX_TIME_DRIFT    (2*60*60)     // the furthest in the future a block is allowed to be timestamped
#define MAX_PROOF_OF_WORK 0x1d00ffffu   // highest value for difficulty target (higher values are less difficult)
#define TARGET_TIMESPAN   (14*24*60*60) // the targeted timespan between difficulty target adjustments

// from https://en.bitcoin.it/wiki/Protocol_specification#Merkle_Trees
// Merkle trees are binary trees of hashes. Merkle trees in bitcoin use a double SHA-256, the SHA-256 hash of the
// SHA-256 hash of something. If, when forming a row in the tree (other than the root of the tree), it would have an odd
// number of elements, the final double-hash is duplicated to ensure that the row has an even number of hashes. First
// form the bottom row of the tree with the ordered double-SHA-256 hashes of the byte streams of the transactions in the
// block. Then the row above it consists of half that number of hashes. Each entry is the double-SHA-256 of the 64-byte
// concatenation of the corresponding two hashes below it in the tree. This procedure repeats recursively until we reach
// a row consisting of just a single double-hash. This is the merkle root of the tree.
//
// from https://github.com/bitcoin/bips/blob/master/bip-0037.mediawiki#Partial_Merkle_branch_format
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
// flag bits (little endian): 00001011 [merkleRoot = 1, m1 = 1, tx1 = 0, tx2 = 1, m2 = 0, byte padding = 000]
// hashes: [tx1, tx2, m2]

@interface BRMerkleBlock ()

@property (nonatomic, strong) NSData *blockHash;
    
@end

@implementation BRMerkleBlock

// message can be either a merkleblock or header message
+ (instancetype)blockWithMessage:(NSData *)message
{
    return [[self alloc] initWithMessage:message];
}

- (instancetype)initWithMessage:(NSData *)message
{
    if (! (self = [self init])) return nil;
    
    if (message.length < 80) return nil;

    NSUInteger off = 0, l = 0, len = 0;
    NSMutableData *d = [NSMutableData data];

    _version = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _prevBlock = [message hashAtOffset:off];
    off += CC_SHA256_DIGEST_LENGTH;
    _merkleRoot = [message hashAtOffset:off];
    off += CC_SHA256_DIGEST_LENGTH;
    _timestamp = [message UInt32AtOffset:off] - NSTimeIntervalSince1970;
    off += sizeof(uint32_t);
    _target = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _nonce = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _totalTransactions = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    len = (NSUInteger)[message varIntAtOffset:off length:&l]*CC_SHA256_DIGEST_LENGTH;
    off += l;
    _hashes = (off + len > message.length) ? nil : [message subdataWithRange:NSMakeRange(off, len)];
    off += len;
    _flags = [message dataAtOffset:off length:&l];
    _height = BLOCK_UNKOWN_HEIGHT;
    
    [d appendUInt32:_version];
    [d appendData:_prevBlock];
    [d appendData:_merkleRoot];
    [d appendUInt32:_timestamp + NSTimeIntervalSince1970 + 0.1];
    [d appendUInt32:_target];
    [d appendUInt32:_nonce];
    _blockHash = d.SHA256_2;

    return self;
}

- (instancetype)initWithBlockHash:(NSData *)blockHash version:(uint32_t)version prevBlock:(NSData *)prevBlock
merkleRoot:(NSData *)merkleRoot timestamp:(NSTimeInterval)timestamp target:(uint32_t)target nonce:(uint32_t)nonce
totalTransactions:(uint32_t)totalTransactions hashes:(NSData *)hashes flags:(NSData *)flags height:(uint32_t)height
{
    if (! (self = [self init])) return nil;
    
    _blockHash = blockHash;
    _version = version;
    _prevBlock = prevBlock;
    _merkleRoot = merkleRoot;
    _timestamp = timestamp;
    _target = target;
    _nonce = nonce;
    _totalTransactions = totalTransactions;
    _hashes = hashes;
    _flags = flags;
    _height = height;
    
    return self;
}

// true if merkle tree and timestamp are valid, and proof-of-work matches the stated difficulty target
// NOTE: This only checks if the block difficulty matches the difficulty target in the header. It does not check if the
// target is correct for the block's height in the chain. Use verifyDifficultyFromPreviousBlock: for that.
- (BOOL)isValid
{
    // target is in "compact" format, where the most significant byte is the size of resulting value in bytes, the next
    // bit is the sign, and the remaining 23bits is the value after having been right shifted by (size - 3)*8 bits
    static const uint32_t maxsize = MAX_PROOF_OF_WORK >> 24, maxtarget = MAX_PROOF_OF_WORK & 0x00ffffffu;
    const uint32_t *b = _blockHash.bytes, size = _target >> 24, target = _target & 0x00ffffffu;
    NSMutableData *d = [NSMutableData data];
    int hashIdx = 0, flagIdx = 0;
    NSData *merkleRoot =
        [self _walk:&hashIdx :&flagIdx :0 :^id (NSData *hash, BOOL flag) {
            return hash;
        } :^id (id left, id right) {
            [d setData:left];
            [d appendData:(right) ? right : left]; // if right branch is missing, duplicate left branch
            return d.SHA256_2;
        }];
    
    if (_totalTransactions > 0 && ! [merkleRoot isEqual:_merkleRoot]) return NO; // merkle root check failed
    
    //TODO: use estimated network time instead of system time (avoids timejacking attacks and misconfigured time)
    if (_timestamp > [NSDate timeIntervalSinceReferenceDate] + MAX_TIME_DRIFT) return NO; // timestamp too far in future
    
    // check if proof-of-work target is out of range
    if (target == 0 || target & 0x00800000u || size > maxsize || (size == maxsize && target > maxtarget)) return NO;

    d = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    if (size > 3) *(uint32_t *)((uint8_t *)d.mutableBytes + size - 3) = CFSwapInt32HostToLittle(target);
    else *(uint32_t *)d.mutableBytes = CFSwapInt32HostToLittle(target >> (3 - size)*8);
    
    for (int i = CC_SHA256_DIGEST_LENGTH/sizeof(uint32_t) - 1; i >= 0; i--) { // check proof-of-work
        if (CFSwapInt32LittleToHost(b[i]) < CFSwapInt32LittleToHost(((const uint32_t *)d.bytes)[i])) break;
        if (CFSwapInt32LittleToHost(b[i]) > CFSwapInt32LittleToHost(((const uint32_t *)d.bytes)[i])) return NO;
    }
    
    return YES;
}

- (NSData *)toData
{
    NSMutableData *d = [NSMutableData data];
    
    [d appendUInt32:_version];
    [d appendData:_prevBlock];
    [d appendData:_merkleRoot];
    [d appendUInt32:_timestamp + NSTimeIntervalSince1970 + 0.1];
    [d appendUInt32:_target];
    [d appendUInt32:_nonce];
    [d appendUInt32:_totalTransactions];
    [d appendVarInt:_hashes.length/CC_SHA256_DIGEST_LENGTH];
    [d appendData:_hashes];
    [d appendVarInt:_flags.length];
    [d appendData:_flags];
    
    return d;
}

// true if the given tx hash is included in the block
- (BOOL)containsTxHash:(NSData *)txHash
{
    for (NSUInteger i = 0; i < _hashes.length/CC_SHA256_DIGEST_LENGTH; i += CC_SHA256_DIGEST_LENGTH) {
        if ([txHash isEqual:[_hashes hashAtOffset:i]]) return YES;
    }
    
    return NO;
}

// returns an array of the matched tx hashes
- (NSArray *)txHashes
{
    int hashIdx = 0, flagIdx = 0;
    NSArray *txHashes =
        [self _walk:&hashIdx :&flagIdx :0 :^id (NSData *hash, BOOL flag) {
            return (flag && hash) ? @[hash] : @[];
        } :^id (id left, id right) {
            return [left arrayByAddingObjectsFromArray:right];
        }];
    
    return txHashes;
}

// Verifies the block difficulty target is correct for the block's position in the chain. Transition time may be 0 if
// height is not a multiple of BLOCK_DIFFICULTY_INTERVAL.
//
// The difficulty target algorithm works as follows:
// The target must be the same as in the previous block unless the block's height is a multiple of 2016. Every 2016
// blocks there is a difficulty transition where a new difficulty is calculated. The new target is the previous target
// multiplied by the time between the last transition block's timestamp and this one (in seconds), divided by the
// targeted time between transitions (14*24*60*60 seconds). If the new difficulty is more than 4x or less than 1/4 of
// the previous difficulty, the change is limited to either 4x or 1/4. There is also a minimum difficulty value
// intuitively named MAX_PROOF_OF_WORK... since larger values are less difficult.
- (BOOL)verifyDifficultyFromPreviousBlock:(BRMerkleBlock *)previous andTransitionTime:(NSTimeInterval)time
{
    if (! [_prevBlock isEqual:previous.blockHash] || _height != previous.height + 1) return NO;
    if ((_height % BLOCK_DIFFICULTY_INTERVAL) == 0 && time == 0) return NO;

#if BITCOIN_TESTNET
    //TODO: implement testnet difficulty rule check
    return YES; // don't worry about difficulty on testnet for now
#endif

    if ((_height % BLOCK_DIFFICULTY_INTERVAL) != 0) return (_target == previous.target) ? YES : NO;

    // target is in "compact" format, explained in isValid:
    static const uint32_t maxsize = MAX_PROOF_OF_WORK >> 24, maxtarget = MAX_PROOF_OF_WORK & 0x00ffffffu;
    uint32_t size = previous.target >> 24;
    double target = previous.target & 0x00ffffffu;
    int32_t timespan = (int32_t)((int64_t)(previous.timestamp + DBL_EPSILON*previous.timestamp) -
                                 (int64_t)(time + DBL_EPSILON*time));

    // limit difficulty transition to -75% or +400%
    if (timespan < TARGET_TIMESPAN/4) timespan = TARGET_TIMESPAN/4;
    if (timespan > TARGET_TIMESPAN*4) timespan = TARGET_TIMESPAN*4;

    target *= timespan;
    target /= TARGET_TIMESPAN;
    
    // normalize target for "compact" format
    while ((uint32_t)(target + DBL_EPSILON*target) < 0x00080000u) target *= 256, size--;
    while ((uint32_t)(target + DBL_EPSILON*target) > 0x007fffffu) target /= 256, size++;
    
    // limit to MAX_PROOF_OF_WORK
    if (size > maxsize || (size == maxsize && target > maxtarget)) target = maxtarget, size = maxsize;
    
    return (_target == ((uint32_t)(target + DBL_EPSILON*target) | size << 24)) ? YES : NO;
}

// recursively walks the merkle tree in depth first order, calling leaf(hash, flag) for each stored hash, and
// branch(left, right) with the result from each branch
- (id)_walk:(int *)hashIdx :(int *)flagIdx :(int)depth :(id (^)(NSData *, BOOL))leaf :(id (^)(id, id))branch
{
    if ((*flagIdx)/8 >= _flags.length || (*hashIdx + 1)*CC_SHA256_DIGEST_LENGTH > _hashes.length) return leaf(nil, NO);
    
    BOOL flag = (((const uint8_t *)_flags.bytes)[*flagIdx/8] & (1 << (*flagIdx % 8)));
    
    (*flagIdx)++;
    
    if (! flag || depth == (int)(ceil(log2(_totalTransactions)) + DBL_EPSILON*_totalTransactions)) {
        NSData *hash = [_hashes hashAtOffset:(*hashIdx)*CC_SHA256_DIGEST_LENGTH];
        
        (*hashIdx)++;
        return leaf(hash, flag);
    }
    
    id left = [self _walk:hashIdx :flagIdx :depth + 1 :leaf :branch];
    id right = [self _walk:hashIdx :flagIdx :depth + 1 :leaf :branch];
    
    return branch(left, right);
}

- (NSUInteger)hash
{
    if (_blockHash.length < sizeof(NSUInteger)) return [super hash];
    return *(const NSUInteger *)_blockHash.bytes;
}

- (BOOL)isEqual:(id)object
{
    return self == object || ([object isKindOfClass:[BRMerkleBlock class]] && [[object blockHash] isEqual:_blockHash]);
}

@end

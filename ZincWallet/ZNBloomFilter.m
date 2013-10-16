//
//  ZNBloomFilter.m
//  ZincWallet
//
//  Created by Aaron Voisine on 10/15/13.
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

#import "ZNBloomFilter.h"
#import "NSMutableData+Bitcoin.h"

#define MAX_BLOOM_FILTER_SIZE 36000
#define MAX_HASH_FUNCS        50

#define ROTL32(x, r) ((x << r) | (x >> (32 - r)))

// murmurHash3 (x86_32): http://code.google.com/p/smhasher/source/browse/trunk/MurmurHash3.cpp
static uint32_t murmurHash3(NSData *data, uint32_t seed)
{
    static const uint32_t c1 = 0xcc9e2d51, c2 = 0x1b873593;
    uint32_t h1 = seed, k1;
    const uint8_t *b = data.bytes;
    NSUInteger blocks = (data.length/4)*4;
    
    for (NSUInteger i = 0; i < blocks; i += 4) {
        k1 = (uint32_t)b[i] | ((uint32_t)b[i + 1] << 8) | ((uint32_t)b[i + 2] << 16) | ((uint32_t)b[i + 3] << 24);
        k1 *= c1;
        k1 = ROTL32(k1, 15);
        k1 *= c2;
        h1 ^= k1;
        h1 = ROTL32(h1, 13);
        h1 = h1*5 + 0xe6546b64;
    }
    
    k1 = 0;
    
    switch (data.length & 3) {
        case 3:
            k1 ^= (b[blocks + 2] & 0xff) << 16;
            // fall through
        case 2:
            k1 ^= (b[blocks + 1] & 0xff) << 8;
            // fall through
        case 1:
            k1 ^= (b[blocks] & 0xff);
            k1 *= c1;
            k1 = ROTL32(k1, 15);
            k1 *= c2;
            h1 ^= k1;
    }
    
    h1 ^= data.length;
    h1 ^= h1 >> 16;
    h1 *= 0x85ebca6b;
    h1 ^= h1 >> 13;
    h1 *= 0xc2b2ae35;
    h1 ^= h1 >> 16;
    
    return h1;
}


@interface ZNBloomFilter ()

@property (nonatomic, strong) NSMutableData *filter;
@property (nonatomic, assign) uint32_t hashFuncs;

@end

@implementation ZNBloomFilter

+ (instancetype)filterWithFalsePositiveRate:(double)fpRate forElementCount:(NSUInteger)count tweak:(uint32_t)tweak
flags:(uint8_t)flags
{
    return [[self alloc] initWithFalsePositiveRate:fpRate forElementCount:count tweak:tweak flags:flags];
}

- (instancetype)initWithFalsePositiveRate:(double)fpRate forElementCount:(NSUInteger)count tweak:(uint32_t)tweak
flags:(uint8_t)flags
{
    if (! (self = [super init])) return nil;

    NSUInteger size = MAX(1, (-1/pow(M_LN2, 2)*count*log(fpRate))/8);

    self.filter = [NSMutableData dataWithLength:size > MAX_BLOOM_FILTER_SIZE ? MAX_BLOOM_FILTER_SIZE : size];
    self.hashFuncs = self.filter.length*8/(double)count*M_LN2;
    if (self.hashFuncs > MAX_HASH_FUNCS) self.hashFuncs = MAX_HASH_FUNCS;
    _tweak = tweak;
    _flags = flags;
    
    return self;
}

- (uint32_t)hash:(NSData *)data hashNum:(uint32_t)hashNum
{
    return murmurHash3(data, hashNum*0xFBA4C795 + self.tweak) % (self.filter.length*8);
}

- (void)insertData:(NSData *)data
{
    uint8_t *b = self.filter.mutableBytes;

    for (uint32_t i = 0; i < self.hashFuncs; i++) {
        uint32_t idx = [self hash:data hashNum:i];

        b[idx >> 3] |= (1 << (7 & idx));
    }
}

- (BOOL)containsData:(NSData *)data
{
    const uint8_t *b = self.filter.bytes;
    
    for (uint32_t i = 0; i < self.hashFuncs; i++) {
        uint32_t idx = [self hash:data hashNum:i];
        
        if (! (b[idx >> 3] & (1 << (7 & idx)))) return NO;
    }

    return YES;
}

- (NSData *)toData
{
    NSMutableData *d = [NSMutableData data];
    
    [d appendVarInt:self.filter.length];
    [d appendData:self.filter];
    [d appendUInt32:self.hashFuncs];
    [d appendUInt32:self.tweak];
    [d appendUInt8:self.flags];

    return d;
}

@end

//
//  NSData+Hash.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "NSData+Hash.h"
#import <CommonCrypto/CommonDigest.h>
#import <openssl/ripemd.h>

extern CFAllocatorRef SecureAllocator();

@implementation NSData (Hash)

- (NSData *)SHA256
{
    NSMutableData *d = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    
    CC_SHA256(self.bytes, self.length, d.mutableBytes);
    
    return d;
}

- (NSData *)SHA256_2
{
    NSMutableData *d = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    
    CC_SHA256(self.bytes, self.length, d.mutableBytes);
    CC_SHA256(d.bytes, d.length, d.mutableBytes);
    
    return d;
}

- (NSData *)RMD160
{
    NSMutableData *d = [NSMutableData dataWithLength:RIPEMD160_DIGEST_LENGTH];
    
    RIPEMD160(self.bytes, self.length, d.mutableBytes);
    
    return d;
}

- (NSData *)hash160
{
    return [[self SHA256] RMD160];
}

- (NSData *)reverse
{
    size_t l = self.length;
    NSMutableData *d = [NSMutableData dataWithLength:l];
    uint8_t *b1 = d.mutableBytes;
    const uint8_t *b2 = self.bytes;
    
    for (size_t i = 0; i < l; i++) {
        b1[i] = b2[l - i - 1];
    }
    
    return d;
}

@end

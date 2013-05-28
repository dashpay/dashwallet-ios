//
//  ZNElectrumSequence.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/27/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNElectrumSequence.h"
#import "ZNKey.h"

#import <CommonCrypto/CommonDigest.h>
//#import <openssl/sha.h>

@implementation ZNElectrumSequence

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed
{
    NSData *pubkey = [[[ZNKey alloc] initWithSecret:[self stretchKey:seed] compressed:NO] publicKey];

    // uncompressed pubkeys are prepended with 0x04... some sort of openssl key encapsulation
    return [NSData dataWithBytes:(uint8_t *)pubkey.bytes + 1 length:pubkey.length - 1];
}

- (NSData *)stretchKey:(NSData *)seed
{
    NSMutableData *d = [NSMutableData dataWithData:seed];
    
    [d appendData:seed];
    if (d.length < CC_SHA256_DIGEST_LENGTH) d.length = CC_SHA256_DIGEST_LENGTH;
    
    CC_SHA256(d.bytes, seed.length*2, d.mutableBytes);
    //SHA256(d.bytes, d.length, d.mutableBytes);
    
    d.length = CC_SHA256_DIGEST_LENGTH;
    [d appendData:seed];
    
    CC_LONG l = CC_SHA256_DIGEST_LENGTH + seed.length;
    unsigned char *md = d.mutableBytes;

    //NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
    
    for (NSUInteger i = 1; i < 100000; i++) {
        CC_SHA256(md, l, md); // commoncrypto takes about 0.32s on a 4th gen ipod touch
        //SHA256(md, l, md);  // openssl takes about 1.95s on a 4th gen ipod touch (not hardware accelerated)
    }

    //NSLog(@"100000 sha256 rounds took %fs", [NSDate timeIntervalSinceReferenceDate] - t);
    
    return [NSData dataWithBytes:d.bytes length:CC_SHA256_DIGEST_LENGTH];
}

@end

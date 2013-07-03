//
//  ZNElectrumSequence.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/27/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNElectrumSequence.h"
#import "ZNKey.h"
#import "NSData+Hash.h"
#import "NSString+Base58.h"
#import <CommonCrypto/CommonDigest.h>
#import <openssl/ecdsa.h>
#import <openssl/obj_mac.h>

@implementation ZNElectrumSequence

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed
{
    NSData *pubkey = [[ZNKey keyWithSecret:[self stretchKey:seed] compressed:NO] publicKey];
    
    if (! pubkey) return nil;

    // uncompressed pubkeys are prepended with 0x04... some sort of openssl key encapsulation
    return [NSData dataWithBytes:(uint8_t *)pubkey.bytes + 1 length:pubkey.length - 1];
}

- (NSData *)stretchKey:(NSData *)seed
{
    if (! seed) return nil;

    NSMutableData *d = [NSMutableData dataWithData:seed];
    
    [d appendData:seed];
    if (d.length < CC_SHA256_DIGEST_LENGTH) d.length = CC_SHA256_DIGEST_LENGTH;
    
    CC_SHA256(d.bytes, seed.length*2, d.mutableBytes);
    //SHA256(d.bytes, seed.length*2, d.mutableBytes);
    
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

- (NSData *)sequence:(NSUInteger)n forChange:(BOOL)forChange masterPublicKey:(NSData *)masterPublicKey
{
    if (! masterPublicKey) return nil;
    
    NSString *s = [NSString stringWithFormat:@"%u:%d:", n, forChange ? 1 : 0];
    NSMutableData *d = [NSMutableData dataWithBytes:s.UTF8String
                        length:[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    
    [d appendData:masterPublicKey];
    
    return [d SHA256_2];
}

- (NSData *)publicKey:(NSUInteger)n forChange:(BOOL)forChange masterPublicKey:(NSData *)masterPublicKey
{
    if (! masterPublicKey) return nil;

    NSData *z = [self sequence:n forChange:forChange masterPublicKey:masterPublicKey];
    BIGNUM *zbn = BN_bin2bn(z.bytes, z.length, NULL);
    BN_CTX *ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    EC_POINT *masterPubKeyPoint = EC_POINT_new(group), *pubKeyPoint = EC_POINT_new(group),
             *zPoint = EC_POINT_new(group);
    uint8_t form = EC_GROUP_get_point_conversion_form(group);
    NSMutableData *d = [NSMutableData dataWithBytes:&form length:1];
    [d appendData:masterPublicKey];

    EC_POINT_oct2point(group, masterPubKeyPoint, d.bytes, d.length, ctx);
    EC_POINT_mul(group, zPoint, zbn, NULL, NULL, ctx);
    EC_POINT_add(group, pubKeyPoint, masterPubKeyPoint, zPoint, ctx);
    d.length = EC_POINT_point2oct(group, pubKeyPoint, form, d.mutableBytes, d.length, ctx);

    EC_POINT_free(zPoint);
    EC_POINT_free(pubKeyPoint);
    EC_POINT_free(masterPubKeyPoint);
    EC_GROUP_free(group);
    BN_CTX_free(ctx);
    BN_free(zbn);
    
    return d;
}

- (NSString *)privateKey:(NSUInteger)n forChange:(BOOL)forChange fromSeed:(NSData *)seed
{
    return [[self privateKeys:@[@(n)] forChange:forChange fromSeed:seed] lastObject];
}

- (NSArray *)privateKeys:(NSArray *)n forChange:(BOOL)forChange fromSeed:(NSData *)seed
{
    if (! seed || ! n.count) return @[];

    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:n.count];
    NSData *secexp = [self stretchKey:seed];
    NSData *mpk = [[ZNKey keyWithSecret:secexp compressed:NO] publicKey];
    BN_CTX *ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    __block BIGNUM *order = BN_new(), *sequencebn = nil, *secexpbn = nil;

    mpk = [NSData dataWithBytes:(uint8_t *)mpk.bytes + 1 length:mpk.length - 1]; // trim leading 0x04 byte
    EC_GROUP_get_order(group, order, ctx);
    
    [n enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSData *sequence = [self sequence:[obj unsignedIntegerValue] forChange:forChange masterPublicKey:mpk];
        NSMutableData *pk = [NSMutableData dataWithLength:33];

        sequencebn = BN_bin2bn(sequence.bytes, sequence.length, sequencebn);
        secexpbn = BN_bin2bn(secexp.bytes, secexp.length, secexpbn);
        
        BN_mod_add(secexpbn, secexpbn, sequencebn, order, ctx);

        *(unsigned char *)pk.mutableBytes = 0x80;
        BN_bn2bin(secexpbn, (unsigned char *)pk.mutableBytes + pk.length - BN_num_bytes(secexpbn));
        
        [ret addObject:[NSString base58checkWithData:pk]];
    }];
    
    BN_free(secexpbn);
    BN_free(sequencebn);
    BN_free(order);
    EC_GROUP_free(group);
    BN_CTX_free(ctx);

    return ret;
}

@end

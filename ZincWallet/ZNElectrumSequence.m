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
    NSData *pubKey = [[ZNKey keyWithSecret:[self stretchKey:seed] compressed:NO] publicKey];
    
    if (! pubKey) return nil;

    // uncompressed pubkeys are prepended with 0x04... some sort of openssl key encapsulation
    return [pubKey subdataWithRange:NSMakeRange(1, pubKey.length - 1)];
}

- (NSData *)stretchKey:(NSData *)seed
{
    if (! seed) return nil;
    
    // Electurm uses a hex representation of the seed instead of the seed itself
    NSString *hex = [NSString hexWithData:seed];
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), 0));
    
    d.length = hex.length*2;
    [hex getBytes:d.mutableBytes maxLength:hex.length usedLength:NULL encoding:NSUTF8StringEncoding options:0
     range:NSMakeRange(0, hex.length) remainingRange:NULL];
    [hex getBytes:(char *)d.mutableBytes + hex.length maxLength:hex.length usedLength:NULL encoding:NSUTF8StringEncoding
     options:0 range:NSMakeRange(0, hex.length) remainingRange:NULL];
    
    if (d.length < CC_SHA256_DIGEST_LENGTH) d.length = CC_SHA256_DIGEST_LENGTH;
    
    CC_SHA256(d.bytes, d.length, d.mutableBytes);
    
    d.length = CC_SHA256_DIGEST_LENGTH + hex.length;
    [hex getBytes:(char *)d.mutableBytes + CC_SHA256_DIGEST_LENGTH maxLength:hex.length usedLength:NULL
     encoding:NSUTF8StringEncoding options:0 range:NSMakeRange(0, hex.length) remainingRange:NULL];
    
    unsigned char *md = d.mutableBytes;
    CC_LONG l = d.length;
    
    for (NSUInteger i = 1; i < 100000; i++) {
        CC_SHA256(md, l, md);
    }
    
    d.length = CC_SHA256_DIGEST_LENGTH;
    return d;
}

- (NSData *)sequence:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
{
    if (! masterPublicKey) return nil;
    
    NSString *s = [NSString stringWithFormat:@"%u:%d:", n, internal ? 1 : 0];
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), s.length + masterPublicKey.length));
    
    [d appendBytes:s.UTF8String length:[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    [d appendData:masterPublicKey];
    
    return [d SHA256_2];
}

- (NSData *)publicKey:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
{
    if (! masterPublicKey) return nil;

    NSData *z = [self sequence:n internal:internal masterPublicKey:masterPublicKey];
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM zbn;
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    EC_POINT *masterPubKeyPoint = EC_POINT_new(group), *pubKeyPoint = EC_POINT_new(group),
             *zPoint = EC_POINT_new(group);
    uint8_t form = EC_GROUP_get_point_conversion_form(group);
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), 0));

    [d appendBytes:&form length:1];
    [d appendData:masterPublicKey];

    BN_init(&zbn);
    BN_bin2bn(z.bytes, z.length, &zbn);
    EC_POINT_oct2point(group, masterPubKeyPoint, d.bytes, d.length, ctx);
    EC_POINT_mul(group, zPoint, &zbn, NULL, NULL, ctx);
    EC_POINT_add(group, pubKeyPoint, masterPubKeyPoint, zPoint, ctx);
    d.length = EC_POINT_point2oct(group, pubKeyPoint, form, d.mutableBytes, d.length, ctx);

    EC_POINT_clear_free(zPoint);
    EC_POINT_clear_free(pubKeyPoint);
    EC_POINT_clear_free(masterPubKeyPoint);
    EC_GROUP_free(group);
    BN_clear_free(&zbn);
    BN_CTX_free(ctx);
    return d;
}

- (NSString *)privateKey:(NSUInteger)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    return [[self privateKeys:@[@(n)] internal:internal fromSeed:seed] lastObject];
}

- (NSArray *)privateKeys:(NSArray *)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    if (! seed || ! n.count) return @[];

    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:n.count];
    NSData *secexp = [self stretchKey:seed];
    NSData *mpk = [[ZNKey keyWithSecret:secexp compressed:NO] publicKey];
    BN_CTX *ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    __block BIGNUM order, sequencebn, secexpbn;

    BN_init(&order);
    BN_init(&sequencebn);
    BN_init(&secexpbn);
    mpk = [mpk subdataWithRange:NSMakeRange(1, mpk.length - 1)]; // trim leading 0x04 byte
    EC_GROUP_get_order(group, &order, ctx);
    
    [n enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSData *sequence = [self sequence:[obj unsignedIntegerValue] internal:internal masterPublicKey:mpk];
        NSMutableData *pk = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), 33));

        BN_bin2bn(sequence.bytes, sequence.length, &sequencebn);
        BN_bin2bn(secexp.bytes, secexp.length, &secexpbn);
        
        BN_mod_add(&secexpbn, &secexpbn, &sequencebn, &order, ctx);

        pk.length = 33;
        *(unsigned char *)pk.mutableBytes = 0x80;
        BN_bn2bin(&secexpbn, (unsigned char *)pk.mutableBytes + pk.length - BN_num_bytes(&secexpbn));
        
        [ret addObject:[NSString base58checkWithData:pk]];
    }];
    
    BN_clear_free(&secexpbn);
    BN_clear_free(&sequencebn);
    BN_free(&order);
    EC_GROUP_free(group);
    BN_CTX_free(ctx);

    return ret;
}

@end

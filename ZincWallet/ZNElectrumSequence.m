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

#import <CommonCrypto/CommonDigest.h>
#import <openssl/ecdsa.h>
#import <openssl/obj_mac.h>

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
    NSString *s = [NSString stringWithFormat:@"%u:%d:", n, forChange ? 1 : 0];
    NSMutableData *d = [NSMutableData dataWithBytes:s.UTF8String
                        length:[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    
    [d appendData:masterPublicKey];
    
    return [d SHA256_2];
}

- (NSData *)publicKey:(NSUInteger)n forChange:(BOOL)forChange masterPublicKey:(NSData *)masterPublicKey
{
    BN_CTX *ctx = BN_CTX_new();
    NSData *z = [self sequence:n forChange:forChange masterPublicKey:masterPublicKey];
    BIGNUM *zbn = BN_bin2bn(z.bytes, z.length, NULL);
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
    BN_free(zbn);
    BN_CTX_free(ctx);

    return d;
}

- (NSData *)privateKey:(NSUInteger)n forChange:(BOOL)forChange fromSeed:(NSData *)seed
{
    return [[self privateKeys:@[@(n)] forChange:forChange fromSeed:seed] lastObject];
}

- (NSArray *)privateKeys:(NSArray *)n forChange:(BOOL)forChange fromSeed:(NSData *)seed
{
//    def get_private_key_from_stretched_exponent(self, sequence, secexp):
//        order = generator_secp256k1.order()
//        secexp = ( secexp + self.get_sequence(sequence, self.mpk) ) % order
//        pk = number_to_string( secexp, generator_secp256k1.order() )
//        compressed = False
//        return SecretToASecret( pk, compressed )
//        
//    def get_private_key(self, sequence, seed):
//        secexp = self.stretch_key(seed)
//        return self.get_private_key_from_stretched_exponent(sequence, secexp)

    return nil;
}

@end

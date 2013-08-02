//
//  ZNBIP32Sequence.m
//  ZincWallet
//
//  Created by Administrator on 7/19/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNBIP32Sequence.h"
#import "ZNKey.h"
#import "NSString+Base58.h"
#import <CommonCrypto/CommonHMAC.h>
#import <openssl/ecdsa.h>
#import <openssl/obj_mac.h>

#define BIP32_PRIME    0x80000000
#define BIP32_SEED_KEY "Bitcoin seed"
#define BIP32_XPRV     "\x04\x88\xAD\xE4"
#define BIP32_XPUB     "\x04\x88\xB2\x1E"

@implementation ZNBIP32Sequence

// To define CKD((kpar, cpar), i) -> (ki, ci):
//
// - Check whether the highest bit (0x80000000) of i is set:
//     - If 1, private derivation is used: let I = HMAC-SHA512(Key = cpar, Data = 0x00 || kpar || i)
//       [Note: The 0x00 pads the private key to make it 33 bytes long.]
//     - If 0, public derivation is used: let I = HMAC-SHA512(Key = cpar, Data = X(kpar*G) || i)
// - Split I = Il || Ir into two 32-byte sequences, Il and Ir.
// - ki = Il + kpar (mod n).
// - ci = Ir.
- (void)CKDForKey:(NSMutableData *)k chain:(NSMutableData *)c n:(uint32_t)n
{
    NSMutableData *data = [NSMutableData dataWithLength:33 - k.length];
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];
    BN_CTX *ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    BIGNUM order, Ilbn, kbn;

    if (n & BIP32_PRIME) [data appendData:k];
    else [data setData:[[ZNKey keyWithSecret:k compressed:YES] publicKey]];

    n = CFSwapInt32HostToBig(n);
    [data appendBytes:&n length:sizeof(n)];

    CCHmac(kCCHmacAlgSHA512, c.bytes, c.length, data.bytes, data.length, I.mutableBytes);

    BN_init(&order);
    BN_init(&Ilbn);
    BN_init(&kbn);
    EC_GROUP_get_order(group, &order, ctx);
    BN_bin2bn(I.bytes, 32, &Ilbn);
    BN_bin2bn(k.bytes, k.length, &kbn);

    BN_mod_add(&kbn, &Ilbn, &kbn, &order, ctx);
    
    k.length = 32;
    BN_bn2bin(&kbn, (unsigned char *)k.mutableBytes + 32 - BN_num_bytes(&kbn));
    [c replaceBytesInRange:NSMakeRange(0, c.length) withBytes:(unsigned char *)I.bytes + 32 length:32];

    BN_clear_free(&kbn);
    BN_clear_free(&Ilbn);
    BN_free(&order);
    EC_GROUP_free(group);
    BN_CTX_free(ctx);
    OPENSSL_cleanse(data.mutableBytes, data.length);
    OPENSSL_cleanse(I.mutableBytes, I.length);
}

// To define CKD'((Kpar, cpar), i) -> (Ki, ci):
//
// - Check whether the highest bit (0x80000000) of i is set:
//     - If 1, return error
//     - If 0, let I = HMAC-SHA512(Key = cpar, Data = X(Kpar) || i)
// - Split I = Il || Ir into two 32-byte sequences, Il and Ir.
// - Ki = (Il + kpar)*G = Il*G + Kpar
// - ci = Ir.
- (void)CKDPrimeForKey:(NSMutableData *)K chain:(NSMutableData *)c n:(uint32_t)n
{
    if (n & BIP32_PRIME) {
        @throw [NSException exceptionWithName:@"ZNPrivateCKDException"
                reason:@"Can't derive private child key from public parent key." userInfo:nil];
    }
    
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];
    NSMutableData *data = [NSMutableData dataWithData:K];
    BN_CTX *ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    uint8_t form = POINT_CONVERSION_COMPRESSED;
    EC_POINT *pubKeyPoint = EC_POINT_new(group), *IlPoint = EC_POINT_new(group);
    BIGNUM Ilbn;

    n = CFSwapInt32HostToBig(n);
    [data appendBytes:&n length:sizeof(n)];

    CCHmac(kCCHmacAlgSHA512, c.bytes, c.length, data.bytes, data.length, I.mutableBytes);

    EC_GROUP_set_point_conversion_form(group, form);
    EC_POINT_oct2point(group, pubKeyPoint, K.bytes, K.length, ctx);
    BN_bin2bn(I.bytes, 32, &Ilbn);
    EC_POINT_mul(group, IlPoint, &Ilbn, NULL, NULL, ctx);
    EC_POINT_add(group, pubKeyPoint, IlPoint, pubKeyPoint, ctx);

    K.length = EC_POINT_point2oct(group, pubKeyPoint, form, NULL, 0, ctx);
    EC_POINT_point2oct(group, pubKeyPoint, form, K.mutableBytes, K.length, ctx);
    [c replaceBytesInRange:NSMakeRange(0, c.length) withBytes:(unsigned char *)I.bytes + 32 length:32];

    BN_clear_free(&Ilbn);
    EC_POINT_clear_free(IlPoint);
    EC_POINT_clear_free(pubKeyPoint);
    EC_GROUP_free(group);
    BN_CTX_free(ctx);
    OPENSSL_cleanse(data.mutableBytes, data.length);
    OPENSSL_cleanse(I.mutableBytes, I.length);
}

#pragma mark - ZNKeySequence

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed
{
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];

    CCHmac(kCCHmacAlgSHA512, BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length, I.mutableBytes);

    NSMutableData *secret = [NSMutableData dataWithBytes:I.bytes length:32];
    NSMutableData *chain = [NSMutableData dataWithBytes:(unsigned char *)I.bytes + 32 length:32];
    NSData *parFingerprint = [[[ZNKey keyWithSecret:secret compressed:YES] hash160] subdataWithRange:NSMakeRange(0, 4)];
    
    [self CKDForKey:secret chain:chain n:0 | BIP32_PRIME]; // account 0'
    
    NSMutableData *mpk =
        CFBridgingRelease(CFDataCreateMutableCopy(SecureAllocator(), 0, (__bridge CFDataRef)(parFingerprint)));

    [mpk appendData:chain];
    [mpk appendData:[[ZNKey keyWithSecret:secret compressed:YES] publicKey]];

    OPENSSL_cleanse(I.mutableBytes, I.length);
    OPENSSL_cleanse(secret.mutableBytes, secret.length);
    OPENSSL_cleanse(chain.mutableBytes, chain.length);
    return mpk;
}

- (NSData *)publicKey:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
{
    if (! masterPublicKey) return nil;

    NSMutableData *chain = [NSMutableData dataWithBytes:(unsigned char *)masterPublicKey.bytes + 4 length:32];
    NSMutableData *pubKey = [NSMutableData dataWithBytes:(unsigned char *)masterPublicKey.bytes + 36
                             length:masterPublicKey.length - 36];

    [self CKDPrimeForKey:pubKey chain:chain n:internal ? 1 : 0]; // internal or external chain
    [self CKDPrimeForKey:pubKey chain:chain n:n]; // nth key in chain

    NSData *ret = CFBridgingRelease(CFDataCreateCopy(SecureAllocator(), (__bridge CFDataRef)(pubKey)));

    OPENSSL_cleanse(chain.mutableBytes, chain.length);
    OPENSSL_cleanse(pubKey.mutableBytes, pubKey.length);
    return ret;
}

- (NSString *)privateKey:(NSUInteger)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    return [[self privateKeys:@[@(n)] internal:internal fromSeed:seed] lastObject];
}

- (NSArray *)privateKeys:(NSArray *)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    if (! seed || ! n.count) return @[];

    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:n.count];
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];

    CCHmac(kCCHmacAlgSHA512, BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length, I.mutableBytes);

    NSMutableData *secret = [NSMutableData dataWithBytes:I.mutableBytes length:32];
    NSMutableData *chain = [NSMutableData dataWithBytes:(unsigned char *)I.mutableBytes + 32 length:32];

    [self CKDForKey:secret chain:chain n:0 | BIP32_PRIME]; // account 0'
    [self CKDForKey:secret chain:chain n:(internal ? 1 : 0)]; // internal or external chain

    for (NSNumber *num in n) {
        NSMutableData *pk = [NSMutableData dataWithBytes:"\x80" length:1];
        NSMutableData *s = [NSMutableData dataWithData:secret];
        NSMutableData *c = [NSMutableData dataWithData:chain];

        [self CKDForKey:s chain:c n:num.unsignedIntegerValue]; // nth key in chain
        [pk appendData:s];
        [pk appendBytes:"\x01" length:1]; // specifies compressed pubkey format
        [ret addObject:[NSString base58checkWithData:pk]];

        OPENSSL_cleanse(pk.mutableBytes, pk.length);
        OPENSSL_cleanse(s.mutableBytes, s.length);
        OPENSSL_cleanse(c.mutableBytes, c.length);
    }

    OPENSSL_cleanse(I.mutableBytes, I.length);
    OPENSSL_cleanse(secret.mutableBytes, secret.length);
    OPENSSL_cleanse(chain.mutableBytes, chain.length);
    return ret;
}

#pragma mark - serializations

- (NSString *)serializeDepth:(uint8_t)depth fingerprint:(uint32_t)fingerprint child:(uint32_t)child
chain:(NSData *)chain key:(NSData *)key
{
    NSMutableData *d = [NSMutableData dataWithBytes:key.length < 33 ? BIP32_XPRV : BIP32_XPUB length:4];
    
    fingerprint = CFSwapInt32HostToBig(fingerprint);
    child = CFSwapInt32HostToBig(child);
    
    [d appendBytes:&depth length:1];
    [d appendBytes:&fingerprint length:sizeof(fingerprint)];
    [d appendBytes:&child length:sizeof(child)];
    [d appendData:chain];
    if (key.length < 33) [d appendBytes:"\0" length:1];
    [d appendData:key];
    
    NSString *ret = [NSString base58checkWithData:d];
    
    OPENSSL_cleanse(d.mutableBytes, d.length);
    return ret;
}

- (NSString *)serializedPrivateMasterFromSeed:(NSData *)seed
{
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];
    
    CCHmac(kCCHmacAlgSHA512, BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length, I.mutableBytes);
    
    NSData *secret = [NSData dataWithBytesNoCopy:I.mutableBytes length:32 freeWhenDone:NO];
    NSData *chain = [NSData dataWithBytesNoCopy:(unsigned char *)I.mutableBytes + 32 length:32 freeWhenDone:NO];

    NSString *ret = [self serializeDepth:0 fingerprint:0 child:0 chain:chain key:secret];

    OPENSSL_cleanse(I.mutableBytes, I.length);
    return ret;
}

- (NSString *)serializedMasterPublicKey:(NSData *)masterPublicKey
{
    uint32_t fingerprint = CFSwapInt32BigToHost(*(uint32_t *)masterPublicKey.bytes);
    NSData *chain = [NSData dataWithBytesNoCopy:(unsigned char *)masterPublicKey.bytes + 4 length:32 freeWhenDone:NO];
    NSData *pubKey = [NSData dataWithBytesNoCopy:(unsigned char *)masterPublicKey.bytes + 36
                      length:masterPublicKey.length - 36 freeWhenDone:NO];

    return [self serializeDepth:1 fingerprint:fingerprint child:0 | BIP32_PRIME chain:chain key:pubKey];
}


@end

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
- (void)CKDForKey:(NSData **)k chain:(NSData **)c n:(uint32_t)n
{
    NSMutableData *data = [NSMutableData dataWithLength:33 - [*k length]];
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];
    BN_CTX *ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    BIGNUM *order = BN_new(), *Ilbn = nil, *kbn = nil;

    if (n & BIP32_PRIME) [data appendData:*k];
    else [data setData:[[ZNKey keyWithSecret:*k compressed:YES] publicKey]];

    n = CFSwapInt32HostToBig(n);
    [data appendBytes:&n length:sizeof(n)];

    CCHmac(kCCHmacAlgSHA512, [*c bytes], [*c length], data.bytes, data.length, I.mutableBytes);

    EC_GROUP_get_order(group, order, ctx);
    Ilbn = BN_bin2bn(I.bytes, 32, Ilbn);
    kbn = BN_bin2bn([*k bytes], [*k length], kbn);

    BN_mod_add(kbn, Ilbn, kbn, order, ctx);
    
    *k = [NSMutableData dataWithLength:32];
    BN_bn2bin(kbn, (unsigned char *)[(NSMutableData *)*k mutableBytes] + 32 - BN_num_bytes(kbn));
    *c = [I subdataWithRange:NSMakeRange(32, 32)];

    BN_free(kbn);
    BN_free(Ilbn);
    BN_free(order);
    EC_GROUP_free(group);
    BN_CTX_free(ctx);
}

// To define CKD'((Kpar, cpar), i) -> (Ki, ci):
//
// - Check whether the highest bit (0x80000000) of i is set:
//     - If 1, return error
//     - If 0, let I = HMAC-SHA512(Key = cpar, Data = X(Kpar) || i)
// - Split I = Il || Ir into two 32-byte sequences, Il and Ir.
// - Ki = (Il + kpar)*G = Il*G + Kpar
// - ci = Ir.
- (void)CKDPrimeForKey:(NSData **)K chain:(NSData **)c n:(uint32_t)n
{
    if (n & BIP32_PRIME) {
        @throw [NSException exceptionWithName:@"ZNPrivateCKDException"
                reason:@"Can't derive private child key from public parent key." userInfo:nil];
    }
    
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];
    NSMutableData *data = [NSMutableData dataWithData:*K];
    BN_CTX *ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    uint8_t form = POINT_CONVERSION_COMPRESSED;
    EC_POINT *pubKeyPoint = EC_POINT_new(group), *IlPoint = EC_POINT_new(group);
    BIGNUM *Ilbn = BN_new();

    n = CFSwapInt32HostToBig(n);
    [data appendBytes:&n length:sizeof(n)];

    CCHmac(kCCHmacAlgSHA512, [*c bytes], [*c length], data.bytes, data.length, I.mutableBytes);

    EC_GROUP_set_point_conversion_form(group, form);
    EC_POINT_oct2point(group, pubKeyPoint, [*K bytes], [*K length], ctx);
    Ilbn = BN_bin2bn(I.bytes, 32, Ilbn);
    EC_POINT_mul(group, IlPoint, Ilbn, NULL, NULL, ctx);
    EC_POINT_add(group, pubKeyPoint, IlPoint, pubKeyPoint, ctx);

    *K = [NSMutableData dataWithLength:EC_POINT_point2oct(group, pubKeyPoint, form, NULL, 0, ctx)];
    EC_POINT_point2oct(group, pubKeyPoint, form, [(NSMutableData *)*K mutableBytes], [*K length], ctx);
    *c = [I subdataWithRange:NSMakeRange(32, 32)];

    BN_free(Ilbn);
    EC_POINT_free(IlPoint);
    EC_POINT_free(pubKeyPoint);
    EC_GROUP_free(group);
    BN_CTX_free(ctx);
}

#pragma mark - ZNKeySequence

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed
{
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];

    CCHmac(kCCHmacAlgSHA512, BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length, I.mutableBytes);

    NSData *secret = [I subdataWithRange:NSMakeRange(0, 32)];
    NSData *chain = [I subdataWithRange:NSMakeRange(32, 32)];
    NSData *pFpr = [[[ZNKey keyWithSecret:secret compressed:YES] hash160] subdataWithRange:NSMakeRange(0, 4)];
    
    [self CKDForKey:&secret chain:&chain n:0 | BIP32_PRIME]; // account 0'
    
    NSMutableData *mpk = [NSMutableData dataWithData:pFpr];

    [mpk appendData:chain];
    [mpk appendData:[[ZNKey keyWithSecret:secret compressed:YES] publicKey]];

    return mpk;
}

- (NSData *)publicKey:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
{
    if (! masterPublicKey) return nil;

    NSData *chain = [masterPublicKey subdataWithRange:NSMakeRange(4, 32)];
    NSData *pubKey = [masterPublicKey subdataWithRange:NSMakeRange(36, masterPublicKey.length - 36)];

    [self CKDPrimeForKey:&pubKey chain:&chain n:internal ? 1 : 0]; // internal or external chain
    [self CKDPrimeForKey:&pubKey chain:&chain n:n]; // nth key in chain

    return pubKey;
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

    NSData *secret = [I subdataWithRange:NSMakeRange(0, 32)], *s;
    NSData *chain = [I subdataWithRange:NSMakeRange(32, 32)], *c;

    [self CKDForKey:&secret chain:&chain n:0 | BIP32_PRIME]; // account 0'
    [self CKDForKey:&secret chain:&chain n:(internal ? 1 : 0)]; // internal or external chain

    for (NSNumber *num in n) {
        NSMutableData *pk = [NSMutableData dataWithBytes:"\x80" length:1];

        s = secret;
        c = chain;
        [self CKDForKey:&s chain:&c n:num.unsignedIntegerValue]; // nth key in chain
        [pk appendData:s];
        [pk appendBytes:"\x01" length:1]; // specifies compressed pubkey format
        [ret addObject:[NSString base58checkWithData:pk]];
    }

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
    
    return [NSString base58checkWithData:d];
}

- (NSString *)serializedPrivateMasterFromSeed:(NSData *)seed
{
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];
    
    CCHmac(kCCHmacAlgSHA512, BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length, I.mutableBytes);
    
    NSData *secret = [I subdataWithRange:NSMakeRange(0, 32)];
    NSData *chain = [I subdataWithRange:NSMakeRange(32, 32)];

    return [self serializeDepth:0 fingerprint:0 child:0 chain:chain key:secret];
}

- (NSString *)serializedMasterPublicKey:(NSData *)masterPublicKey
{
    NSData *pFpr = [masterPublicKey subdataWithRange:NSMakeRange(0, 4)];
    NSData *chain = [masterPublicKey subdataWithRange:NSMakeRange(4, 32)];
    NSData *pubKey = [masterPublicKey subdataWithRange:NSMakeRange(36, masterPublicKey.length - 36)];
    uint32_t fingerprint = CFSwapInt32BigToHost(*(uint32_t *)pFpr.bytes);
    
    return [self serializeDepth:1 fingerprint:fingerprint child:0 | BIP32_PRIME chain:chain key:pubKey];
}


@end

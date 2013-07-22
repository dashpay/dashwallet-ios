//
//  ZNBIP32Sequence.m
//  ZincWallet
//
//  Created by Administrator on 7/19/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNBIP32Sequence.h"
#import "ZNKey.h"
#import "NSData+Hash.h"
#import "NSString+Base58.h"
#import <CommonCrypto/CommonHMAC.h>
#import <openssl/ecdsa.h>
#import <openssl/obj_mac.h>

#define BIP32_PRIME 0x80000000
#define BIP32_MASTER_HMAC_KEY "Bitcoin seed"

@implementation ZNBIP32Sequence

- (void)CKDForKey:(NSData **)k chain:(NSData **)c n:(uint32_t)n
{
//    import hmac
//    from ecdsa.util import string_to_number, number_to_string
//    order = generator_secp256k1.order()
//    keypair = EC_KEY(string_to_number(k))
//    K = GetPubKey(keypair.pubkey,True)
//
//    if n & BIP32_PRIME:
//        data = chr(0) + k + rev_hex(int_to_hex(n,4)).decode('hex')
//        I = hmac.new(c, data, hashlib.sha512).digest()
//    else:
//        I = hmac.new(c, K + rev_hex(int_to_hex(n,4)).decode('hex'), hashlib.sha512).digest()
//
//    k_n = number_to_string( (string_to_number(I[0:32]) + string_to_number(k)) % order , order )
//    c_n = I[32:]
//    return k_n, c_n

    NSMutableData *data = [NSMutableData data];
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];
    BN_CTX *ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    BIGNUM *order = BN_new(), *Ilbn = nil, *kbn = nil, *bn = nil;

    if (n & BIP32_PRIME) {
        [data appendBytes:"\0" length:1];
        [data appendData:*k];
    }
    else [data appendData:[[ZNKey keyWithSecret:*k compressed:YES] publicKey]];

    n = CFSwapInt32HostToBig(n);
    [data appendBytes:&n length:sizeof(n)];

    CCHmac(kCCHmacAlgSHA512, [*k bytes], [*k length], data.bytes, data.length, I.mutableBytes);

    EC_GROUP_get_order(group, order, ctx);
    Ilbn = BN_bin2bn(I.bytes, 32, Ilbn);
    kbn = BN_bin2bn([*k bytes], [*k length], kbn);

    BN_mod_add(Ilbn, kbn, bn, order, ctx);
    
    *k = [NSMutableData dataWithLength:BN_num_bytes(bn)];
    BN_bn2bin(bn, [(NSMutableData *)*k mutableBytes]);
    *c = [I subdataWithRange:NSMakeRange(32, 32)];

    BN_free(bn);
    BN_free(kbn);
    BN_free(Ilbn);
    BN_free(order);
    EC_GROUP_free(group);
    BN_CTX_free(ctx);
}

- (void)CKDPrimeForKey:(NSData **)K chain:(NSData **)c n:(uint32_t)n
{
//    import hmac
//    from ecdsa.util import string_to_number, number_to_string
//    order = generator_secp256k1.order()
//
//    if n & BIP32_PRIME: raise
//
//    K_public_key = ecdsa.VerifyingKey.from_string( K, curve = SECP256k1 )
//    K_compressed = GetPubKey(K_public_key.pubkey,True)
//
//    I = hmac.new(c, K_compressed + rev_hex(int_to_hex(n,4)).decode('hex'), hashlib.sha512).digest()
//
//    curve = SECP256k1
//    pubkey_point = string_to_number(I[0:32])*curve.generator + K_public_key.pubkey.point
//    public_key = ecdsa.VerifyingKey.from_public_point( pubkey_point, curve = SECP256k1 )
//
//    K_n = public_key.to_string()
//    K_n_compressed = GetPubKey(public_key.pubkey,True)
//    c_n = I[32:]
//        
//    return K_n, K_n_compressed, c_n

    if (n & BIP32_PRIME) {
        @throw [NSException exceptionWithName:@"ZNPrivateCKDException"
                reason:@"Can't derive private child key from public parent key." userInfo:nil];
    }
    
    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];
    NSMutableData *data = [NSMutableData dataWithData:*K];
    BN_CTX *ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    uint8_t form = EC_GROUP_get_point_conversion_form(group);
    EC_POINT *pubKeyPoint = EC_POINT_new(group), *IlPoint = EC_POINT_new(group);
    BIGNUM *Ilbn = BN_new();

    n = CFSwapInt32HostToBig(n);
    [data appendBytes:&n length:sizeof(n)];

    CCHmac(kCCHmacAlgSHA512, [*c bytes], [*c length], data.bytes, data.length, I.mutableBytes);

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

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed chain:(NSData **)c
{
//    def bip32_init(seed):
//        import hmac
//        seed = seed.decode('hex')
//        I = hmac.new("Bitcoin seed", seed, hashlib.sha512).digest()
//
//        master_secret = I[0:32]
//        master_chain = I[32:]
//
//        K, K_compressed = get_pubkeys_from_secret(master_secret)
//        return master_secret, master_chain, K, K_compressed
//
//    master_secret, master_chain, master_public_key, master_public_key_compressed = bip32_init(seed)
//    return master_public_key.encode('hex'), master_chain.encode('hex')

    NSMutableData *I = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];

    CCHmac(kCCHmacAlgSHA512, BIP32_MASTER_HMAC_KEY, strlen(BIP32_MASTER_HMAC_KEY), seed.bytes, seed.length,
           I.mutableBytes);

    *c = [I subdataWithRange:NSMakeRange(32, 32)];

    return [[ZNKey keyWithSecret:[I subdataWithRange:NSMakeRange(0, 32)] compressed:YES] publicKey];

//    NSData *pubkey = [[ZNKey keyWithSecret:[self stretchKey:seed] compressed:NO] publicKey];
//
//    if (! pubkey) return nil;
//
//    // uncompressed pubkeys are prepended with 0x04... some sort of openssl key encapsulation
//    return [NSData dataWithBytes:(uint8_t *)pubkey.bytes + 1 length:pubkey.length - 1];
}

//- (NSData *)sequence:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
//{
//    if (! masterPublicKey) return nil;
//
//    NSString *s = [NSString stringWithFormat:@"%u:%d:", n, internal ? 1 : 0];
//    NSMutableData *d = [NSMutableData dataWithBytes:s.UTF8String
//                        length:[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
//
//    [d appendData:masterPublicKey];
//
//    return [d SHA256_2];
//}

- (NSData *)publicKey:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
{
//    if (! masterPublicKey) return nil;
//
//    NSData *z = [self sequence:n internal:internal masterPublicKey:masterPublicKey];
//    BIGNUM *zbn = BN_bin2bn(z.bytes, z.length, NULL);
//    BN_CTX *ctx = BN_CTX_new();
//    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
//    EC_POINT *masterPubKeyPoint = EC_POINT_new(group), *pubKeyPoint = EC_POINT_new(group),
//             *zPoint = EC_POINT_new(group);
//    uint8_t form = EC_GROUP_get_point_conversion_form(group);
//    NSMutableData *d = [NSMutableData dataWithBytes:&form length:1];
//    [d appendData:masterPublicKey];
//
//    EC_POINT_oct2point(group, masterPubKeyPoint, d.bytes, d.length, ctx);
//    EC_POINT_mul(group, zPoint, zbn, NULL, NULL, ctx);
//    EC_POINT_add(group, pubKeyPoint, masterPubKeyPoint, zPoint, ctx);
//    d.length = EC_POINT_point2oct(group, pubKeyPoint, form, d.mutableBytes, d.length, ctx);
//
//    EC_POINT_free(zPoint);
//    EC_POINT_free(pubKeyPoint);
//    EC_POINT_free(masterPubKeyPoint);
//    EC_GROUP_free(group);
//    BN_CTX_free(ctx);
//    BN_free(zbn);
//
//    return d;
    return nil;
}

- (NSString *)privateKey:(NSUInteger)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
//    return [[self privateKeys:@[@(n)] internal:internal fromSeed:seed] lastObject];
    return nil;
}

- (NSArray *)privateKeys:(NSArray *)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
//    if (! seed || ! n.count) return @[];
//
//    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:n.count];
//    NSData *secexp = [self stretchKey:seed];
//    NSData *mpk = [[ZNKey keyWithSecret:secexp compressed:NO] publicKey];
//    BN_CTX *ctx = BN_CTX_new();
//    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
//    __block BIGNUM *order = BN_new(), *sequencebn = nil, *secexpbn = nil;
//
//    mpk = [NSData dataWithBytes:(uint8_t *)mpk.bytes + 1 length:mpk.length - 1]; // trim leading 0x04 byte
//    EC_GROUP_get_order(group, order, ctx);
//
//    [n enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
//        NSData *sequence = [self sequence:[obj unsignedIntegerValue] internal:internal masterPublicKey:mpk];
//        NSMutableData *pk = [NSMutableData dataWithLength:33];
//
//        sequencebn = BN_bin2bn(sequence.bytes, sequence.length, sequencebn);
//        secexpbn = BN_bin2bn(secexp.bytes, secexp.length, secexpbn);
//
//        BN_mod_add(secexpbn, secexpbn, sequencebn, order, ctx);
//
//        *(unsigned char *)pk.mutableBytes = 0x80;
//        BN_bn2bin(secexpbn, (unsigned char *)pk.mutableBytes + pk.length - BN_num_bytes(secexpbn));
//
//        [ret addObject:[NSString base58checkWithData:pk]];
//    }];
//
//    BN_free(secexpbn);
//    BN_free(sequencebn);
//    BN_free(order);
//    EC_GROUP_free(group);
//    BN_CTX_free(ctx);
//    
//    return ret;
    return nil;
}

@end

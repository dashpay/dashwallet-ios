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
#define BIP32_SEED_KEY "Bitcoin seed"

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
//
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
//
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

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed
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

    CCHmac(kCCHmacAlgSHA512, BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length, I.mutableBytes);

    NSData *masterSecret = [I subdataWithRange:NSMakeRange(0, 32)];
    NSData *masterChain = [I subdataWithRange:NSMakeRange(32, 32)];
    NSMutableData *mpk = [NSMutableData dataWithData:[[ZNKey keyWithSecret:masterSecret compressed:YES] publicKey]];

    [mpk appendData:masterChain];

    return mpk;

//    NSData *pubkey = [[ZNKey keyWithSecret:[self stretchKey:seed] compressed:NO] publicKey];
//
//    if (! pubkey) return nil;
//
//    // uncompressed pubkeys are prepended with 0x04... some sort of openssl key encapsulation
//    return [NSData dataWithBytes:(uint8_t *)pubkey.bytes + 1 length:pubkey.length - 1];
}

- (NSData *)publicKey:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
{
    if (! masterPublicKey) return nil;

    NSData *pubKey = [masterPublicKey subdataWithRange:NSMakeRange(0, masterPublicKey.length - 32)];
    NSData *chain = [masterPublicKey subdataWithRange:NSMakeRange(masterPublicKey.length - 32, 32)];

    [self CKDPrimeForKey:&pubKey chain:&chain n:0]; // account 0
    [self CKDPrimeForKey:&pubKey chain:&chain n:internal ? 1 : 0]; // internal or external chain
    [self CKDPrimeForKey:&pubKey chain:&chain n:n]; // nth key in chain

    return pubKey;

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

    [self CKDForKey:&secret chain:&chain n:0 | BIP32_PRIME]; // account 0
    [self CKDForKey:&secret chain:&chain n:(internal ? 1 : 0)]; // internal or external chain

    for (NSNumber *num in n) {
        NSMutableData *pk = [NSMutableData dataWithBytes:"\x80" length:1];

        s = secret;
        c = chain;
        [self CKDForKey:&s chain:&c n:num.unsignedIntegerValue | BIP32_PRIME]; // nth key in chain
        [pk appendData:s];
        [ret addObject:[NSString base58checkWithData:pk]];
    }

    return ret;

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
}

@end

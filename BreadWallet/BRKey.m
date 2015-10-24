//
//  BRKey.m
//  BreadWallet
//
//  Created by Aaron Voisine on 5/22/13.
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

#import "BRKey.h"
#import "NSString+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"

#define HAVE_CONFIG_H 1
#define DETERMINISTIC 1

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wconversion"
#pragma clang diagnostic ignored "-Wunused-function"
#import "secp256k1/src/secp256k1.c"
#pragma clang diagnostic pop

static secp256k1_context_t *_ctx = NULL;

// add 256bit big endian ints (mod secp256k1 order)
UInt256 secp256k1_mod_add(UInt256 a, UInt256 b)
{
    secp256k1_scalar_t as, bs, rs;
    UInt256 r;
    
    secp256k1_scalar_set_b32(&as, a.u8, NULL);
    secp256k1_scalar_set_b32(&bs, b.u8, NULL);
    secp256k1_scalar_add(&rs, &as, &bs);
    secp256k1_scalar_clear(&bs);
    secp256k1_scalar_clear(&as);
    secp256k1_scalar_get_b32((unsigned char *)&r, &rs);
    secp256k1_scalar_clear(&rs);
    return r;
}

// multiply 256bit big endian ints (mod secp256k1 order)
UInt256 secp256k1_mod_mul(UInt256 a, UInt256 b)
{
    secp256k1_scalar_t as, bs, rs;
    UInt256 r;
    
    secp256k1_scalar_set_b32(&as, a.u8, NULL);
    secp256k1_scalar_set_b32(&bs, b.u8, NULL);
    secp256k1_scalar_mul(&rs, &as, &bs);
    secp256k1_scalar_clear(&bs);
    secp256k1_scalar_clear(&as);
    secp256k1_scalar_get_b32(r.u8, &rs);
    secp256k1_scalar_clear(&rs);
    return r;
}

// add secp256k1 ec-points
int secp256k1_point_add(void *r, const void *a, const void *b, int compressed)
{
    secp256k1_ge_t ap, bp, rp;
    secp256k1_gej_t aj, rj;
    int size = 0;

    if (! secp256k1_eckey_pubkey_parse(&ap, a, 33)) return 0;
    if (! secp256k1_eckey_pubkey_parse(&bp, b, 33)) return 0;
    secp256k1_gej_set_ge(&aj, &ap);
    secp256k1_ge_clear(&ap);
    secp256k1_gej_add_ge(&rj, &aj, &bp);
    secp256k1_gej_clear(&aj);
    secp256k1_ge_clear(&bp);
    secp256k1_ge_set_gej(&rp, &rj);
    secp256k1_gej_clear(&rj);
    secp256k1_eckey_pubkey_serialize(&rp, r, &size, compressed);
    secp256k1_ge_clear(&rp);
    return size;
}

// multiply ec-point by 256bit big endian int
int secp256k1_point_mul(void *r, const void *p, UInt256 i, int compressed)
{
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        if (! _ctx) _ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY);
    });

    secp256k1_scalar_t is, zs;
    secp256k1_gej_t rj, pj;
    secp256k1_ge_t rp, pp;
    int size = 0;

    secp256k1_scalar_set_b32(&is, i.u8, NULL);

    if (p) {
        if (! secp256k1_eckey_pubkey_parse(&pp, p, 33)) return 0;
        secp256k1_gej_set_ge(&pj, &pp);
        secp256k1_ge_clear(&pp);
        secp256k1_scalar_clear(&zs);
        secp256k1_ecmult(&_ctx->ecmult_ctx, &rj, &pj, &is, &zs);
        secp256k1_gej_clear(&pj);
    }
    else secp256k1_ecmult_gen(&_ctx->ecmult_gen_ctx, &rj, &is);

    secp256k1_scalar_clear(&is);
    secp256k1_ge_set_gej(&rp, &rj);
    secp256k1_gej_clear(&rj);
    secp256k1_eckey_pubkey_serialize(&rp, r, &size, compressed);
    secp256k1_ge_clear(&rp);
    return size;
}

@interface BRKey ()

@property (nonatomic, assign) UInt256 seckey;
@property (nonatomic, strong) NSData *pubkey;
@property (nonatomic, assign) BOOL compressed;

@end

@implementation BRKey

+ (instancetype)keyWithPrivateKey:(NSString *)privateKey
{
    return [[self alloc] initWithPrivateKey:privateKey];
}

+ (instancetype)keyWithSecret:(UInt256)secret compressed:(BOOL)compressed
{
    return [[self alloc] initWithSecret:secret compressed:compressed];
}

+ (instancetype)keyWithPublicKey:(NSData *)publicKey
{
    return [[self alloc] initWithPublicKey:publicKey];
}

+ (instancetype)keyRecoveredFromCompactSig:(NSData *)compactSig andMessageDigest:(UInt256)md
{
    return [[self alloc] initWithCompactSig:compactSig andMessageDigest:md];
}

- (instancetype)init
{
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        if (! _ctx) _ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY);
    });
    
    return (self = [super init]);
}

- (instancetype)initWithSecret:(UInt256)secret compressed:(BOOL)compressed
{
    if (! (self = [self init])) return nil;

    _seckey = secret;
    _compressed = compressed;
    return (secp256k1_ec_seckey_verify(_ctx, _seckey.u8)) ? self : nil;
}

- (instancetype)initWithPrivateKey:(NSString *)privateKey
{
    if (privateKey.length == 0) return nil;
    if (! (self = [self init])) return nil;
    
    // mini private key format
    if ((privateKey.length == 30 || privateKey.length == 22) && [privateKey characterAtIndex:0] == 'S') {
        if (! [privateKey isValidBitcoinPrivateKey]) return nil;
        
        _seckey = [CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(), (CFStringRef)privateKey,
                                                                          kCFStringEncodingUTF8, 0)) SHA256];
        _compressed = NO;
        return self;
    }
    
    NSData *d = privateKey.base58checkToData;
    uint8_t version = BITCOIN_PRIVKEY;
    
#if BITCOIN_TESTNET
    version = BITCOIN_PRIVKEY_TEST;
#endif
    
    if (! d || d.length == 28) d = privateKey.base58ToData;
    if (d.length < sizeof(UInt256) || d.length > sizeof(UInt256) + 2) d = privateKey.hexToData;
    
    if ((d.length == sizeof(UInt256) + 1 || d.length == sizeof(UInt256) + 2) && *(const uint8_t *)d.bytes == version) {
        _seckey = *(const UInt256 *)((const uint8_t *)d.bytes + 1);
        _compressed = (d.length == sizeof(UInt256) + 2) ? YES : NO;
    }
    else if (d.length == sizeof(UInt256)) _seckey = *(const UInt256 *)d.bytes;
    
    return (secp256k1_ec_seckey_verify(_ctx, _seckey.u8)) ? self : nil;
}

- (instancetype)initWithPublicKey:(NSData *)publicKey
{
    if (publicKey.length == 0) return nil;
    if (! (self = [self init])) return nil;
    
    self.pubkey = publicKey;
    self.compressed = (self.pubkey.length == 33) ? YES : NO;
    return (secp256k1_ec_pubkey_verify(_ctx, self.publicKey.bytes, (int)self.publicKey.length)) ? self : nil;
}

- (instancetype)initWithCompactSig:(NSData *)compactSig andMessageDigest:(UInt256)md
{
    if (compactSig.length != 65) return nil;
    if (! (self = [self init])) return nil;
    
    self.compressed = (((uint8_t *)compactSig.bytes)[0] - 27 >= 4) ? YES : NO;

    int len = (self.compressed ? 33 : 65), recid = (((uint8_t *)compactSig.bytes)[0] - 27) % 4;
    NSMutableData *pubkey = [NSMutableData dataWithLength:len];

    if (secp256k1_ecdsa_recover_compact(_ctx, md.u8, (const uint8_t *)compactSig.bytes + 1, pubkey.mutableBytes, &len,
                                        self.compressed, recid)) {
        _pubkey = pubkey;
        return self;
    }
    
    return nil;
}

- (NSString *)privateKey
{
    if (uint256_is_zero(_seckey)) return nil;

    NSMutableData *d = [NSMutableData secureDataWithCapacity:sizeof(UInt256) + 2];
    uint8_t version = BITCOIN_PRIVKEY;

#if BITCOIN_TESTNET
    version = BITCOIN_PRIVKEY_TEST;
#endif

    [d appendBytes:&version length:1];
    [d appendBytes:&_seckey length:sizeof(_seckey)];
    if (self.compressed) [d appendBytes:"\x01" length:1];
    return [NSString base58checkWithData:d];
}

- (NSData *)publicKey
{
    if (self.pubkey.length == 0 && ! uint256_is_zero(_seckey)) {
        NSMutableData *d = [NSMutableData secureDataWithLength:self.compressed ? 33 : 65];
        int len = 0;

        if (secp256k1_ec_pubkey_create(_ctx, d.mutableBytes, &len, _seckey.u8, _compressed)) {
            self.pubkey = d;
        }
    }
    
    return self.pubkey;
}

- (UInt160)hash160
{
    return self.publicKey.hash160;
}

- (NSString *)address
{
    NSMutableData *d = [NSMutableData secureDataWithCapacity:160/8 + 1];
    uint8_t version = BITCOIN_PUBKEY_ADDRESS;
    UInt160 hash160 = self.hash160;

#if BITCOIN_TESTNET
    version = BITCOIN_PUBKEY_ADDRESS_TEST;
#endif
    
    [d appendBytes:&version length:1];
    [d appendBytes:&hash160 length:sizeof(hash160)];
    return [NSString base58checkWithData:d];
}

- (NSData *)sign:(UInt256)md
{
    if (uint256_is_zero(_seckey)) {
        NSLog(@"%s: can't sign with a public key", __func__);
        return nil;
    }

    NSMutableData *s = [NSMutableData dataWithLength:72];
    int len = (int)s.length;
    
    if (secp256k1_ecdsa_sign(_ctx, md.u8, s.mutableBytes, &len, _seckey.u8, secp256k1_nonce_function_rfc6979, NULL)) {
        s.length = len;
        return s;
    }
    else return nil;
}

- (BOOL)verify:(UInt256)md signature:(NSData *)sig
{
    // success is 1, all other values are fail
    return (secp256k1_ecdsa_verify(_ctx, md.u8, sig.bytes, (int)sig.length, self.publicKey.bytes,
                                   (int)self.publicKey.length) == 1) ? YES : NO;
}

// Pieter Wuille's custom compact signature format used for bitcoin message signing
- (NSData *)compactSign:(UInt256)md
{
    if (uint256_is_zero(_seckey)) {
        NSLog(@"%s: can't sign with a public key", __func__);
        return nil;
    }
    
    NSMutableData *s = [NSMutableData dataWithLength:65];
    int recid = 0;
    
    if (secp256k1_ecdsa_sign_compact(_ctx, md.u8, (uint8_t *)s.mutableBytes + 1, _seckey.u8,
                                     secp256k1_nonce_function_rfc6979, NULL, &recid)) {
        ((uint8_t *)s.mutableBytes)[0] = 27 + recid + (self.compressed ? 4 : 0);
        return s;
    }
    else return nil;
    
}

@end

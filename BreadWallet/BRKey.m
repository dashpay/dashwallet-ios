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

#import <secp256k1/include/secp256k1.h>
#import <secp256k1/src/util.h>
#import <secp256k1/src/scalar_impl.h>
#import <secp256k1/src/field_impl.h>
#import <secp256k1/src/group_impl.h>
#import <secp256k1/src/ecmult_gen_impl.h>
#import <secp256k1/src/ecmult_impl.h>
#import <secp256k1/src/eckey_impl.h>

#define SECKEY_LENGTH (256/8)

// add 256bit big endian ints (mod secp256k1 order)
void secp256k1_mod_add(void *r, const void *a, const void *b)
{
    secp256k1_scalar_t as, bs, rs;
    
    secp256k1_scalar_set_b32(&as, a, NULL);
    secp256k1_scalar_set_b32(&bs, b, NULL);
    secp256k1_scalar_add(&rs, &as, &bs);
    secp256k1_scalar_clear(&bs);
    secp256k1_scalar_clear(&as);
    secp256k1_scalar_get_b32(r, &rs);
    secp256k1_scalar_clear(&rs);
}

// multiply 256bit big endian ints (mod secp256k1 order)
void secp256k1_mod_mul(void *r, const void *a, const void *b)
{
    secp256k1_scalar_t as, bs, rs;
    
    secp256k1_scalar_set_b32(&as, a, NULL);
    secp256k1_scalar_set_b32(&bs, b, NULL);
    secp256k1_scalar_mul(&rs, &as, &bs);
    secp256k1_scalar_clear(&bs);
    secp256k1_scalar_clear(&as);
    secp256k1_scalar_get_b32(r, &rs);
    secp256k1_scalar_clear(&rs);
}

// add secp256k1 points
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

// multiply point by 256bit big endian
int secp256k1_point_mul(void *r, const void *p, const void *i, int compressed)
{
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        secp256k1_ecmult_start();
        secp256k1_ecmult_gen_start();
    });

    secp256k1_scalar_t is, zs;
    secp256k1_gej_t rj, pj;
    secp256k1_ge_t rp, pp;
    int size = 0;

    secp256k1_scalar_set_b32(&is, i, NULL);

    if (p) {
        if (! secp256k1_eckey_pubkey_parse(&pp, p, 33)) return 0;
        secp256k1_gej_set_ge(&pj, &pp);
        secp256k1_ge_clear(&pp);
        secp256k1_scalar_clear(&zs);
        secp256k1_ecmult(&rj, &pj, &is, &zs);
        secp256k1_gej_clear(&pj);
    }
    else secp256k1_ecmult_gen(&rj, &is);

    secp256k1_scalar_clear(&is);
    secp256k1_ge_set_gej(&rp, &rj);
    secp256k1_gej_clear(&rj);
    secp256k1_eckey_pubkey_serialize(&rp, r, &size, compressed);
    secp256k1_ge_clear(&rp);
    return size;
}

@interface BRKey ()

@property (nonatomic, strong) NSData *seckey, *pubkey;
@property (nonatomic, assign) BOOL compressed;

@end

@implementation BRKey

+ (instancetype)keyWithPrivateKey:(NSString *)privateKey
{
    return [[self alloc] initWithPrivateKey:privateKey];
}

+ (instancetype)keyWithSecret:(NSData *)secret compressed:(BOOL)compressed
{
    return [[self alloc] initWithSecret:secret compressed:compressed];
}

+ (instancetype)keyWithPublicKey:(NSData *)publicKey
{
    return [[self alloc] initWithPublicKey:publicKey];
}

- (instancetype)initWithSecret:(NSData *)secret compressed:(BOOL)compressed
{
    if (secret.length != SECKEY_LENGTH) return nil;

    if (! (self = [self init])) return nil;

    self.seckey = secret;
    self.compressed = compressed;
    return (secp256k1_ec_seckey_verify(self.seckey.bytes)) ? self : nil;
}

- (instancetype)initWithPrivateKey:(NSString *)privateKey
{
    if (! (self = [self init])) return nil;
    
    // mini private key format
    if ((privateKey.length == 30 || privateKey.length == 22) && [privateKey characterAtIndex:0] == 'S') {
        if (! [privateKey isValidBitcoinPrivateKey]) return nil;
        
        self.seckey = [CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(),
                       (CFStringRef)privateKey, kCFStringEncodingUTF8, 0)) SHA256];
        self.compressed = NO;
        return self;
    }
    
    NSData *d = privateKey.base58checkToData;
    uint8_t version = BITCOIN_PRIVKEY;
    
#if BITCOIN_TESTNET
    version = BITCOIN_PRIVKEY_TEST;
#endif
    
    if (! d || d.length == 28) d = privateKey.base58ToData;
    if (d.length < SECKEY_LENGTH || d.length > SECKEY_LENGTH + 2) d = privateKey.hexToData;
    
    if ((d.length == SECKEY_LENGTH + 1 || d.length == SECKEY_LENGTH + 2) && *(const uint8_t *)d.bytes == version) {
        self.seckey = CFBridgingRelease(CFDataCreate(SecureAllocator(), (const uint8_t *)d.bytes + 1, SECKEY_LENGTH));
        self.compressed = (d.length == SECKEY_LENGTH + 2) ? YES : NO;
    }
    else if (d.length == SECKEY_LENGTH) self.seckey = d;
    
    return (secp256k1_ec_seckey_verify(self.seckey.bytes)) ? self : nil;
}

- (instancetype)initWithPublicKey:(NSData *)publicKey
{
    if (! (self = [self init])) return nil;
    
    self.pubkey = publicKey;
    self.compressed = (self.pubkey.length == 33) ? YES : NO;
    return (secp256k1_ec_pubkey_verify(self.publicKey.bytes, self.publicKey.length)) ? self : nil;
}

- (NSString *)privateKey
{
    if (self.seckey.length != SECKEY_LENGTH) return nil;

    NSMutableData *d = [NSMutableData secureDataWithCapacity:SECKEY_LENGTH + 2];
    uint8_t version = BITCOIN_PRIVKEY;

#if BITCOIN_TESTNET
    version = BITCOIN_PRIVKEY_TEST;
#endif

    [d appendBytes:&version length:1];
    [d appendData:self.seckey];
    if (self.compressed) [d appendBytes:"\x01" length:1];
    return [NSString base58checkWithData:d];
}

- (NSData *)publicKey
{
    if (! self.pubkey.length && self.seckey.length == SECKEY_LENGTH) {
        static dispatch_once_t onceToken = 0;
        
        dispatch_once(&onceToken, ^{
            secp256k1_start(SECP256K1_START_SIGN);
        });

        NSMutableData *d = [NSMutableData secureDataWithLength:self.compressed ? 33 : 65];
        int size = 0;

        if (secp256k1_ec_pubkey_create(d.mutableBytes, &size, self.seckey.bytes, self.compressed)) self.pubkey = d;
    }
    
    return self.pubkey;
}

- (NSData *)hash160
{
    return self.publicKey.hash160;
}

- (NSString *)address
{
    NSMutableData *d = [NSMutableData secureDataWithCapacity:160/8 + 1];
    uint8_t version = BITCOIN_PUBKEY_ADDRESS;

#if BITCOIN_TESTNET
    version = BITCOIN_PUBKEY_ADDRESS_TEST;
#endif
    
    [d appendBytes:&version length:1];
    [d appendData:self.hash160];
    return [NSString base58checkWithData:d];
}

- (NSData *)sign:(NSData *)md
{
    if (self.seckey.length != SECKEY_LENGTH) {
        NSLog(@"%s: can't sign with a public key", __func__);
        return nil;
    }
    else if (md.length != CC_SHA256_DIGEST_LENGTH) {
        NSLog(@"%s: Only 256bit message digests can be signed", __func__);
        return nil;
    }

    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        secp256k1_start(SECP256K1_START_SIGN);
    });

    NSMutableData *s = [NSMutableData dataWithLength:72];
    int l = s.length;
    
    if (secp256k1_ecdsa_sign(md.bytes, s.mutableBytes, &l, self.seckey.bytes, secp256k1_nonce_function_rfc6979, NULL)) {
        s.length = l;
        return s;
    }
    else return nil;
}

- (BOOL)verify:(NSData *)md signature:(NSData *)sig
{
    if (md.length != CC_SHA256_DIGEST_LENGTH) {
        NSLog(@"%s: Only 256bit message digests can be verified", __func__);
        return NO;
    }

    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        secp256k1_start(SECP256K1_START_VERIFY);
    });

    // success is 1, all other values are fail
    return (secp256k1_ecdsa_verify(md.bytes, sig.bytes, sig.length, self.publicKey.bytes, self.publicKey.length) == 1);
}

@end

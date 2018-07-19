//
//  DSKey.m
//  DashSync
//
//  Created by Aaron Voisine on 5/22/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  Updated by Quantum Explorer on 05/11/18.
//  Copyright (c) 2018 Quantum Explorer <quantum@dash.org>
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

#import "DSKey.h"
#import "NSString+Dash.h"
#import "NSData+Dash.h"
#import "NSString+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Dash.h"
#import "DSChain.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wconversion"
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wconditional-uninitialized"
#import "secp256k1.h"
#import "secp256k1_recovery.h"
#pragma clang diagnostic pop

static secp256k1_context *_ctx = NULL;
static dispatch_once_t _ctx_once = 0;

// adds 256bit big endian ints a and b (mod secp256k1 order) and stores the result in a
// returns true on success
int DSSecp256k1ModAdd(UInt256 *a, const UInt256 *b)
{
    dispatch_once(&_ctx_once, ^{ _ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY); });
    return secp256k1_ec_privkey_tweak_add(_ctx, (unsigned char *)a, (const unsigned char *)b);
}

// multiplies 256bit big endian ints a and b (mod secp256k1 order) and stores the result in a
// returns true on success
int DSSecp256k1ModMul(UInt256 *a, const UInt256 *b)
{
    dispatch_once(&_ctx_once, ^{ _ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY); });
    return secp256k1_ec_privkey_tweak_mul(_ctx, (unsigned char *)a, (const unsigned char *)b);
}

// multiplies secp256k1 generator by 256bit big endian int i and stores the result in p
// returns true on success
int DSSecp256k1PointGen(DSECPoint *p, const UInt256 *i)
{
    secp256k1_pubkey pubkey;
    size_t pLen = sizeof(*p);
    
    dispatch_once(&_ctx_once, ^{ _ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY); });
    return (secp256k1_ec_pubkey_create(_ctx, &pubkey, (const unsigned char *)i) &&
            secp256k1_ec_pubkey_serialize(_ctx, (unsigned char *)p, &pLen, &pubkey, SECP256K1_EC_COMPRESSED));
}

// multiplies secp256k1 generator by 256bit big endian int i and adds the result to ec-point p
// returns true on success
int DSSecp256k1PointAdd(DSECPoint *p, const UInt256 *i)
{
    secp256k1_pubkey pubkey;
    size_t pLen = sizeof(*p);
    
    dispatch_once(&_ctx_once, ^{ _ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY); });
    return (secp256k1_ec_pubkey_parse(_ctx, &pubkey, (const unsigned char *)p, sizeof(*p)) &&
            secp256k1_ec_pubkey_tweak_add(_ctx, &pubkey, (const unsigned char *)i) &&
            secp256k1_ec_pubkey_serialize(_ctx, (unsigned char *)p, &pLen, &pubkey, SECP256K1_EC_COMPRESSED));
}

// multiplies secp256k1 ec-point p by 256bit big endian int i and stores the result in p
// returns true on success
int DSSecp256k1PointMul(DSECPoint *p, const UInt256 *i)
{
    secp256k1_pubkey pubkey;
    size_t pLen = sizeof(*p);
    
    dispatch_once(&_ctx_once, ^{ _ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY); });
    return (secp256k1_ec_pubkey_parse(_ctx, &pubkey, (const unsigned char *)p, sizeof(*p)) &&
            secp256k1_ec_pubkey_tweak_mul(_ctx, &pubkey, (const unsigned char *)i) &&
            secp256k1_ec_pubkey_serialize(_ctx, (unsigned char *)p, &pLen, &pubkey, SECP256K1_EC_COMPRESSED));
}

@interface DSKey ()

@property (nonatomic, assign) UInt256 seckey;
@property (nonatomic, strong) NSData *pubkey;
@property (nonatomic, assign) BOOL compressed;

@end

@implementation DSKey

+ (instancetype)keyWithPrivateKey:(NSString *)privateKey onChain:(DSChain*)chain
{
    return [[self alloc] initWithPrivateKey:privateKey onChain:chain];
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
    dispatch_once(&_ctx_once, ^{ _ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY); });
    return (self = [super init]);
}

- (instancetype)initWithSecret:(UInt256)secret compressed:(BOOL)compressed
{
    if (! (self = [self init])) return nil;

    _seckey = secret;
    _compressed = compressed;
    return (secp256k1_ec_seckey_verify(_ctx, _seckey.u8)) ? self : nil;
}

- (instancetype)initWithPrivateKey:(NSString *)privateKey onChain:(DSChain*)chain
{
    if (privateKey.length == 0) return nil;
    if (! (self = [self init])) return nil;
    
    // mini private key format
    if ((privateKey.length == 30 || privateKey.length == 22) && [privateKey characterAtIndex:0] == 'L') {
        if (! [privateKey isValidDashPrivateKeyOnChain:chain]) return nil;
        
        _seckey = [CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(), (CFStringRef)privateKey,
                                                                          kCFStringEncodingUTF8, 0)) SHA256];
        _compressed = NO;
        return self;
    }
    
    NSData *d = privateKey.base58checkToData;
    uint8_t version;
    if ([chain isMainnet]) {
        version = DASH_PRIVKEY;
    } else {
        version = DASH_PRIVKEY_TEST;
    }
    
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
    if (publicKey.length != 33 && publicKey.length != 65) return nil;
    if (! (self = [self init])) return nil;
    
    secp256k1_pubkey pk;
    
    self.pubkey = publicKey;
    self.compressed = (self.pubkey.length == 33) ? YES : NO;
    return (secp256k1_ec_pubkey_parse(_ctx, &pk, self.publicKey.bytes, self.publicKey.length)) ? self : nil;
}

- (instancetype)initWithCompactSig:(NSData *)compactSig andMessageDigest:(UInt256)md
{
    if (compactSig.length != 65) return nil;
    if (! (self = [self init])) return nil;

    self.compressed = (((uint8_t *)compactSig.bytes)[0] - 27 >= 4) ? YES : NO;
    
    NSMutableData *pubkey = [NSMutableData dataWithLength:(self.compressed ? 33 : 65)];
    size_t len = pubkey.length;
    int recid = (((uint8_t *)compactSig.bytes)[0] - 27) % 4;
    secp256k1_ecdsa_recoverable_signature s;
    secp256k1_pubkey pk;

    if (secp256k1_ecdsa_recoverable_signature_parse_compact(_ctx, &s, (const uint8_t *)compactSig.bytes + 1, recid) &&
        secp256k1_ecdsa_recover(_ctx, &pk, &s, md.u8) &&
        secp256k1_ec_pubkey_serialize(_ctx, pubkey.mutableBytes, &len, &pk,
                                      (self.compressed ? SECP256K1_EC_COMPRESSED : SECP256K1_EC_UNCOMPRESSED))) {
        pubkey.length = len;
        _pubkey = pubkey;
        return self;
    }
    
    return nil;
}

- (NSString *)privateKeyStringForChain:(DSChain*)chain
{
    if (uint256_is_zero(_seckey)) return nil;

    NSMutableData *d = [NSMutableData secureDataWithCapacity:sizeof(UInt256) + 2];
    uint8_t version;
    if ([chain isMainnet]) {
        version = DASH_PRIVKEY;
    } else {
        version = DASH_PRIVKEY_TEST;
    }

    [d appendBytes:&version length:1];
    [d appendBytes:&_seckey length:sizeof(_seckey)];
    if (self.compressed) [d appendBytes:"\x01" length:1];
    return [NSString base58checkWithData:d];
}

- (NSData *)publicKey
{
    if (self.pubkey.length == 0 && ! uint256_is_zero(_seckey)) {
        NSMutableData *d = [NSMutableData secureDataWithLength:self.compressed ? 33 : 65];
        size_t len = d.length;
        secp256k1_pubkey pk;

        if (secp256k1_ec_pubkey_create(_ctx, &pk, _seckey.u8)) {
            secp256k1_ec_pubkey_serialize(_ctx, d.mutableBytes, &len, &pk,
                                          (self.compressed ? SECP256K1_EC_COMPRESSED : SECP256K1_EC_UNCOMPRESSED));
            if (len == d.length) self.pubkey = d;
        }
    }
    
    return self.pubkey;
}

- (UInt160)hash160
{
    return self.publicKey.hash160;
}

- (const UInt256 *)secretKey
{
    return &_seckey;
}

- (NSString *)addressForChain:(DSChain*)chain
{
    NSMutableData *d = [NSMutableData secureDataWithCapacity:160/8 + 1];
    uint8_t version;
    UInt160 hash160 = self.hash160;

    if ([chain isMainnet]) {
        version = DASH_PUBKEY_ADDRESS;
    } else {
        version = DASH_PUBKEY_ADDRESS_TEST;
    }
    
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

    NSMutableData *sig = [NSMutableData dataWithLength:72];
    size_t len = sig.length;
    secp256k1_ecdsa_signature s;
    
    if (secp256k1_ecdsa_sign(_ctx, &s, md.u8, _seckey.u8, secp256k1_nonce_function_rfc6979, NULL) &&
        secp256k1_ecdsa_signature_serialize_der(_ctx, sig.mutableBytes, &len, &s)) {
        sig.length = len;
    }
    else sig = nil;
    
    return sig;
}

- (BOOL)verify:(UInt256)md signature:(NSData *)sig
{
    secp256k1_pubkey pk;
    secp256k1_ecdsa_signature s;
    BOOL r = NO;
    
    if (secp256k1_ec_pubkey_parse(_ctx, &pk, self.publicKey.bytes, self.publicKey.length) &&
        secp256k1_ecdsa_signature_parse_der(_ctx, &s, sig.bytes, sig.length) &&
        secp256k1_ecdsa_verify(_ctx, &s, md.u8, &pk) == 1) { // success is 1, all other values are fail
        r = YES;
    }
    
    return r;
}

// Pieter Wuille's compact signature encoding used for bitcoin message signing
// to verify a compact signature, recover a public key from the signature and verify that it matches the signer's pubkey
- (NSData *)compactSign:(UInt256)md
{
    if (uint256_is_zero(_seckey)) {
        NSLog(@"%s: can't sign with a public key", __func__);
        return nil;
    }
    
    NSMutableData *sig = [NSMutableData dataWithLength:65];
    secp256k1_ecdsa_recoverable_signature s;
    int recid = 0;
    
    if (secp256k1_ecdsa_sign_recoverable(_ctx, &s, md.u8, _seckey.u8, secp256k1_nonce_function_rfc6979, NULL) &&
        secp256k1_ecdsa_recoverable_signature_serialize_compact(_ctx, (uint8_t *)sig.mutableBytes + 1, &recid, &s)) {
        ((uint8_t *)sig.mutableBytes)[0] = 27 + recid + (self.compressed ? 4 : 0);
    }
    else sig = nil;
    
    return sig;
}

@end

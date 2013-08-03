//
//  ZNKey.mm
//  ZincWallet
//
//  Created by Aaron Voisine on 5/22/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNKey.h"
#import "NSString+Base58.h"
#import "NSData+Hash.h"
#import <openssl/ecdsa.h>
#import <openssl/obj_mac.h>

@interface ZNKey ()

@property (nonatomic, assign) EC_KEY *key;

@end

@implementation ZNKey

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

- (instancetype)init
{
    if (! (self = [super init])) return nil;
    
    _key = EC_KEY_new_by_curve_name(NID_secp256k1);
    
    return _key ? self : nil;
}

- (void)dealloc
{
    if (_key) EC_KEY_free(_key);
}

- (instancetype)initWithSecret:(NSData *)secret compressed:(BOOL)compressed
{
    if (secret.length != 32) return nil;

    if (! (self = [self init])) return nil;

    [self setSecret:secret compressed:compressed];
    
    return self;
}

- (instancetype)initWithPrivateKey:(NSString *)privateKey
{
    if (! (self = [self init])) return nil;
    
    self.privateKey = privateKey;
    
    return self;
}

- (instancetype)initWithPublicKey:(NSData *)publicKey
{
    if (! (self = [self init])) return nil;
    
    self.publicKey = publicKey;
    
    return self;
}

- (void)setSecret:(NSData *)secret compressed:(BOOL)compressed
{
    if (secret.length != 32 || ! _key) return;
    
    BN_CTX *ctx = BN_CTX_new();
    const EC_GROUP *group = EC_KEY_get0_group(_key);
    EC_POINT *pub = EC_POINT_new(group);
    BIGNUM priv;
    
    BN_init(&priv);
    
    if (pub && ctx) {
        BN_bin2bn(secret.bytes, 32, &priv);
        if (EC_POINT_mul(group, pub, &priv, NULL, NULL, ctx)) {
            EC_KEY_set_private_key(_key, &priv);
            EC_KEY_set_public_key(_key, pub);
        }
    }
    
    BN_clear_free(&priv);
    if (pub) EC_POINT_free(pub);
    if (ctx) BN_CTX_free(ctx);
    
    EC_KEY_set_conv_form(_key, compressed ? POINT_CONVERSION_COMPRESSED : POINT_CONVERSION_UNCOMPRESSED);
}

- (void)setPrivateKey:(NSString *)privateKey
{
    NSData *d = [privateKey base58checkToData];

    if (! d || d.length == 28) d = [privateKey base58ToData];
    
    if (d.length == 32) {
        [self setSecret:d compressed:YES];
    }
    else if ((d.length == 33 || d.length == 34) && *(unsigned char *)d.bytes == 0x80) {
        [self setSecret:[NSData dataWithBytesNoCopy:(unsigned char *)d.bytes + 1 length:32 freeWhenDone:NO]
         compressed:d.length == 34];
    }
}

- (NSString *)privateKey
{
    const BIGNUM *priv = EC_KEY_get0_private_key(_key);
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), 34));
    
    d.length = (EC_KEY_get_conv_form(_key) == POINT_CONVERSION_COMPRESSED ? 34 : 33);
    *(unsigned char *)d.mutableBytes = 0x80;
    BN_bn2bin(priv, (unsigned char *)d.mutableBytes + 33 - BN_num_bytes(priv));

    return [NSString base58checkWithData:d];
}

- (void)setPublicKey:(NSData *)publicKey
{
    const unsigned char *bytes = publicKey.bytes;

    o2i_ECPublicKey(&_key, &bytes, publicKey.length);
}

- (NSData *)publicKey
{
    if (! EC_KEY_check_key(_key)) return nil;

    size_t l = i2o_ECPublicKey(_key, NULL);
    NSMutableData *pubKey = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), l));
    
    pubKey.length = l;
    
    unsigned char *bytes = pubKey.mutableBytes;
    
    if (i2o_ECPublicKey(_key, &bytes) != l) return nil;
    
    return pubKey;
}

- (NSData *)hash160
{
    return [[self publicKey] hash160];
}

- (NSString *)address
{
    NSData *hash = [self hash160];
    
    if (! hash) return nil;

    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), hash.length + 1));
    uint8_t version = BITCOIN_TESTNET ? BITCOIN_PUBKEY_ADDRESS_TEST : BITCOIN_PUBKEY_ADDRESS;
    
    [d appendBytes:&version length:1];
    [d appendData:hash];

    return [NSString base58checkWithData:d];
}

- (NSData *)sign:(NSData *)d
{
    if (d.length != 256/8) {
        NSLog(@"Only 256 bit hashes can be signed");
        return nil;
    }

    unsigned int l = ECDSA_size(_key);
    NSMutableData *sig = [NSMutableData dataWithLength:l];

    ECDSA_sign(0, d.bytes, d.length, sig.mutableBytes, &l, _key);
    sig.length = l;

    if (! [self verify:d signature:sig]) {
        NSLog(@"Verify failed");
        return nil;
    }

    return sig;
}

- (BOOL)verify:(NSData *)d signature:(NSData *)sig
{
    // -1 = error, 0 = bad sig, 1 = good
    return ECDSA_verify(0, d.bytes, d.length, sig.bytes, sig.length, _key) == 1;
}

@end

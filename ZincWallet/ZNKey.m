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

static void clear_deallocate(void *ptr, void *info)
{
    CFAllocatorContext context;
    
    CFAllocatorGetContext(NULL, &context);
    context.deallocate(ptr, info);
}

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
        BN_bin2bn((unsigned char *)secret.bytes, 32, &priv);
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
        [self setSecret:[NSData dataWithBytesNoCopy:(char *)d.bytes + 1 length:32 freeWhenDone:NO]
         compressed:d.length == 34];
    }
}

- (NSString *)privateKey
{
    const BIGNUM *priv = EC_KEY_get0_private_key(_key);
    point_conversion_form_t form = EC_KEY_get_conv_form(_key);
    NSMutableData *d = [NSMutableData dataWithLength:form == POINT_CONVERSION_COMPRESSED ? 34 : 33];
    
    *(unsigned char *)d.mutableBytes = 0x80;
    BN_bn2bin(priv, (unsigned char *)d.mutableBytes + 33 - BN_num_bytes(priv));

    NSString *s = [NSString base58checkWithData:d];

    OPENSSL_cleanse(d.mutableBytes, d.length);
    return s;
}

- (void)setPublicKey:(NSData *)publicKey
{
    const unsigned char *bytes = (const unsigned char *)publicKey.bytes;

    o2i_ECPublicKey(&_key, &bytes, publicKey.length);
}

- (NSData *)publicKey
{
    if (! EC_KEY_check_key(_key)) return nil;

    NSMutableData *pubKey = [NSMutableData dataWithLength:i2o_ECPublicKey(_key, NULL)];
    unsigned char *bytes = (unsigned char *)pubKey.mutableBytes;
    
    if (i2o_ECPublicKey(_key, &bytes) != pubKey.length) return nil;
    
    return pubKey;
}

- (NSData *)hash160
{
    return [[self publicKey] hash160];
}

- (NSString *)address
{
    uint8_t version = BITCOIN_TESTNET ? BITCOIN_PUBKEY_ADDRESS_TEST : BITCOIN_PUBKEY_ADDRESS;
    NSMutableData *d = [NSMutableData dataWithBytes:&version length:1];
    NSData *hash = [self hash160];
    
    if (! hash) return nil;
    
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

    ECDSA_sign(0, (const unsigned char *)d.bytes, d.length, (unsigned char *)sig.mutableBytes, &l, _key);
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
    return ECDSA_verify(0, (unsigned char *)d.bytes, d.length, (unsigned char *)sig.bytes, sig.length, _key) == 1;
}

@end

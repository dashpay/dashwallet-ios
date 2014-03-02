//
//  ZNKey.m
//  ZincWallet
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
    BIGNUM priv;
    const EC_GROUP *group = EC_KEY_get0_group(_key);
    EC_POINT *pub = EC_POINT_new(group);
    
    BN_init(&priv);
    
    if (pub && ctx) {
        BN_bin2bn(secret.bytes, 32, &priv);
        
        if (EC_POINT_mul(group, pub, &priv, NULL, NULL, ctx)) {
            EC_KEY_set_private_key(_key, &priv);
            EC_KEY_set_public_key(_key, pub);
            EC_KEY_set_conv_form(_key, compressed ? POINT_CONVERSION_COMPRESSED : POINT_CONVERSION_UNCOMPRESSED);
        }
    }
    
    if (pub) EC_POINT_free(pub);
    BN_clear_free(&priv);
    if (ctx) BN_CTX_free(ctx);
}

- (void)setPrivateKey:(NSString *)privateKey
{
    NSData *d = privateKey.base58checkToData;

    if ((privateKey.length == 30 || privateKey.length == 22) && [privateKey characterAtIndex:0] == 'S') {
        // mini private key format
        if (! [privateKey isValidBitcoinPrivateKey]) return;
        
        [self setSecret:[CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(),
                         (__bridge CFStringRef)privateKey, kCFStringEncodingUTF8, 0)) SHA256] compressed:NO];
        return;
    }
    else if (! d || d.length == 28) d = privateKey.base58ToData;
    
    if (d.length == 32) [self setSecret:d compressed:YES];
    else if ((d.length == 33 || d.length == 34) && *(unsigned char *)d.bytes == 0x80) {
        [self setSecret:[NSData dataWithBytesNoCopy:(unsigned char *)d.bytes + 1 length:32 freeWhenDone:NO]
         compressed:(d.length == 34) ? YES : NO];
    }
}

- (NSString *)privateKey
{
    const BIGNUM *priv = EC_KEY_get0_private_key(_key);
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), 34));
    
    [d appendBytes:"\x80" length:1];
    d.length = 33;
    BN_bn2bin(priv, (unsigned char *)d.mutableBytes + d.length - BN_num_bytes(priv));
    if (EC_KEY_get_conv_form(_key) == POINT_CONVERSION_COMPRESSED) [d appendBytes:"\x01" length:1];

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
    
    if (! hash.length) return nil;

    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), hash.length + 1));
#if BITCOIN_TESTNET
    uint8_t version = BITCOIN_PUBKEY_ADDRESS_TEST;
#else
    uint8_t version = BITCOIN_PUBKEY_ADDRESS;
#endif
    
    [d appendBytes:&version length:1];
    [d appendData:hash];

    return [NSString base58checkWithData:d];
}

- (NSData *)sign:(NSData *)d
{
    if (d.length != 256/8) {
        NSLog(@"%s:%d: %s: Only 256 bit hashes can be signed", __FILE__, __LINE__,  __func__);
        return nil;
    }

    unsigned l = ECDSA_size(_key);
    NSMutableData *sig = [NSMutableData dataWithLength:l];
    
    //TODO: XXXX implement RFC6979 deterministic signatures
    //# Test Vectors for RFC 6979 ECDSA, secp256k1, SHA-256
    //# (private key, message, expected k, expected signature)
    //test_vectors = [
    //(0x1, "Satoshi Nakamoto",
    //0x8F8A276C19F4149656B280621E358CCE24F5F52542772691EE69063B74F15D15,
    //"934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d82442ce9d2b916064108014783e923ec36b49743e2ffa1c44"
    //"96f01a512aafd9e5"),
    //(0x1, "All those moments will be lost in time, like tears in rain. Time to die...",
    //0x38AA22D72376B4DBC472E06C3BA403EE0A394DA63FC58D88686C611ABA98D6B3,
    //"8600dbd41e348fe5c9465ab92d23e3db8b98b873beecd930736488696438cb6b547fe64427496db33bf66019dacbf0039c04199abb012291"
    //"8601db38a72cfc21"),
    //(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140, "Satoshi Nakamoto",
    //0x33A19B60E25FB6F4435AF53A3D42D493644827367E6453928554F43E49AA6F90,
    //"fd567d121db66e382991534ada77a6bd3106f0a1098c231e47993447cd6af2d06b39cd0eb1bc8603e159ef5c20a5c8ad685a45b06ce9bebe"
    //"d3f153d10d93bed5"),
    //(0xf8b8af8ce3c7cca5e300d33939540c10d45ce001b8f252bfbc57ba0342904181, "Alan Turing",
    //0x525A82B70E67874398067543FD84C83D30C175FDC45FDEEE082FE13B1D7CFDF1,
    //"7063ae83e7f62bbb171798131b4a0564b956930092b33b07b395615d9ec7e15c58dfcc1e00a35e1572f366ffe34ba0fc47db1e7189759b9f"
    //"b233c5b05ab388ea"),
    //(0xe91671c46231f833a6406ccbea0e3e392c76c167bac1cb013f6f1013980455c2, "There is a computer disease that anybody "
    //"who works with computers knows about. It's a very serious disease and it interferes completely with the work. "
    //"The trouble with computers is that you 'play' with them!",
    //0x1F4B84C23A86A221D233F2521BE018D9318639D5B8BBD6374A8A59232D16AD3D,
    //"b552edd27580141f3b2a5463048cb7cd3e047b97c9f98076c32dbdf85a68718b279fa72dd19bfae05577e06c7c0c1900c371fcd5893f7e1d"
    //"56a37d30174671f6")
    //]
    ECDSA_sign(0, d.bytes, (int)d.length, sig.mutableBytes, &l, _key);
    sig.length = l;

    if (! [self verify:d signature:sig]) {
        NSLog(@"%s:%d: %s: Verify failed", __FILE__, __LINE__,  __func__);
        return nil;
    }

    return sig;
}

- (BOOL)verify:(NSData *)d signature:(NSData *)sig
{
    // -1 = error, 0 = bad sig, 1 = good
    return (ECDSA_verify(0, d.bytes, (int)d.length, sig.bytes, (int)sig.length, _key) == 1) ? YES : NO;
}

@end

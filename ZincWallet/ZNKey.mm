//
//  ZNKey.mm
//  ZincWallet
//
//  Created by Aaron Voisine on 5/22/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNKey.h"
#import "NSString+Base58.h"

#include "key.h"
#include "base58.h"

@interface ZNKey ()

@property (nonatomic, readonly) CKey *key;

@end

@implementation ZNKey

+ (id)keyWithPrivateKey:(NSString *)privateKey
{
    return [[self alloc] initWithPrivateKey:privateKey];
}

+ (id)keyWithSecret:(NSData *)secret compressed:(BOOL)compressed
{
    return [[self alloc] initWithSecret:secret compressed:compressed];
}

+ (id)keyWithPublicKey:(NSData *)publicKey
{
    return [[self alloc] initWithPublicKey:publicKey];
}

- (id)init
{
    if (! (self = [super init])) return nil;
    
    _key = new CKey();
    
    return self;
}

- (void)dealloc
{
    delete _key;
}

- (id)initWithSecret:(NSData *)secret compressed:(BOOL)compressed
{
    if (! (self = [self init])) return nil;
    
    if (secret.length != 32) return nil;
    
    CSecret s((unsigned char *)secret.bytes, (unsigned char *)secret.bytes + secret.length);
    
    _key->SetSecret(s, compressed);
    
    return _key->IsNull() ? nil : self;
}

- (id)initWithPrivateKey:(NSString *)privateKey
{
    if (! (self = [self init])) return nil;
    
    self.privateKey = privateKey;
    
    return _key->IsNull() ? nil : self;
}

- (id)initWithPublicKey:(NSData *)publicKey
{
    if (! (self = [self init])) return nil;
    
    self.publicKey = publicKey;
    
    return _key->IsNull() ? nil : self;
}

- (void)setPrivateKey:(NSString *)privateKey
{
    std::vector<unsigned char>v;
    
    if (! DecodeBase58Check(privateKey.UTF8String, v) || v.size() == 28) {
        DecodeBase58(privateKey.UTF8String, v);
    }
    
    if (v.size() == 32) {
        CSecret secret(&v[0], &v[32]);
        
        _key->SetSecret(secret, TRUE);
    }
    else if ((v.size() == 33 || v.size() == 34) && v[0] == 0x80) {
        CSecret secret(&v[1], &v[33]);
    
        _key->SetSecret(secret, v.size() == 34);
    }
}

- (void)setPublicKey:(NSData *)publicKey
{
    std::vector<unsigned char>v((unsigned char *)publicKey.bytes, (unsigned char *)publicKey.bytes + publicKey.length);

    _key->SetPubKey(v);
}

- (NSData *)publicKey
{
    std::vector<unsigned char>raw = _key->GetPubKey().Raw();
    
    return [NSData dataWithBytes:&raw[0] length:raw.size()];
}

- (NSData *)hash160
{
    CKeyID hash = _key->GetPubKey().GetID();
    
    return [NSData dataWithBytes:&hash length:20];
}

- (NSString *)address
{
    return [NSString stringWithUTF8String:CBitcoinAddress(_key->GetPubKey().GetID()).ToString().c_str()];
}

- (NSData *)sign:(NSData *)d
{
    std::vector<unsigned char>sig;

    if (d.length != 256/8) {
        NSLog(@"Only sign 256bit hashes can be signed");
        return nil;
    }

    std::vector<unsigned char>vch((unsigned char *)d.bytes, (unsigned char *)d.bytes + d.length);
    uint256 hash(vch);

    _key->Sign(hash, sig);

//    if (! _key->Verify(Hash((unsigned char *)d.bytes, (unsigned char *)d.bytes + d.length), sig)) {
//        NSLog(@"Verify failed");
//        return nil;
//    }

    return [NSData dataWithBytes:&sig[0] length:sig.size()];
}

@end

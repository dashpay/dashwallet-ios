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
#include "ui_interface.h"

CClientUIInterface uiInterface; // hack to avoid having to build and link bitcoin/src/init.cpp

@interface ZNKey ()

@property (nonatomic, readonly) CKey *key;
@property (nonatomic, readonly) CPubKey *pubKey;

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
    
    _key = new CKey();
    _pubKey = new CPubKey();
    
    return self;
}

- (void)dealloc
{
    delete _key;
    delete _pubKey;
}

- (instancetype)initWithSecret:(NSData *)secret compressed:(BOOL)compressed
{
    if (! (self = [self init])) return nil;
        
    _key->Set((unsigned char *)secret.bytes, (unsigned char *)secret.bytes + secret.length, compressed);
    
    return _key->IsValid() ? self : nil;
}

- (instancetype)initWithPrivateKey:(NSString *)privateKey
{
    if (! (self = [self init])) return nil;
    
    self.privateKey = privateKey;
    
    return _key->IsValid() ? self : nil;
}

- (instancetype)initWithPublicKey:(NSData *)publicKey
{
    if (! (self = [self init])) return nil;
    
    self.publicKey = publicKey;
    
    return _pubKey->IsValid() ? self : nil;
}

- (void)setPrivateKey:(NSString *)privateKey
{
    std::vector<unsigned char>v;
    
    if (! DecodeBase58Check(privateKey.UTF8String, v) || v.size() == 28) {
        DecodeBase58(privateKey.UTF8String, v);
    }
    
    if (v.size() == 32) {
        _key->Set(&v[0], &v[32], TRUE);
    }
    else if ((v.size() == 33 || v.size() == 34) && v[0] == 0x80) {
        _key->Set(&v[1], &v[33], v.size() == 34);
    }
}

- (void)setPublicKey:(NSData *)publicKey
{
    _pubKey->Set((unsigned char *)publicKey.bytes, (unsigned char *)publicKey.bytes + publicKey.length);
}

- (NSData *)publicKey
{
    CPubKey p = _key->IsValid() ? _key->GetPubKey() : *_pubKey;
    
    if (! p.IsValid()) return nil;
    
    return [NSData dataWithBytes:&p[0] length:p.size()];
}

- (NSData *)hash160
{
    CPubKey p = _key->IsValid() ? _key->GetPubKey() : *_pubKey;

    if (! p.IsValid()) return nil;

    CKeyID hash = p.GetID();
    
    return [NSData dataWithBytes:&hash length:20];
}

- (NSString *)address
{
    CPubKey p = _key->IsValid() ? _key->GetPubKey() : *_pubKey;
    
    if (! p.IsValid()) return nil;
    
    return [NSString stringWithUTF8String:CBitcoinAddress(p.GetID()).ToString().c_str()];
}

- (NSData *)sign:(NSData *)d
{
    std::vector<unsigned char>sig;

    if (d.length != 256/8) {
        NSLog(@"Only sign 256bit hashes can be signed");
        return nil;
    }

    std::vector<unsigned char>v((unsigned char *)d.bytes, (unsigned char *)d.bytes + d.length);
    uint256 hash(v);

    _key->Sign(hash, sig);

//    if (! _key->Verify(Hash((unsigned char *)d.bytes, (unsigned char *)d.bytes + d.length), sig)) {
//        NSLog(@"Verify failed");
//        return nil;
//    }

    return [NSData dataWithBytes:&sig[0] length:sig.size()];
}

@end

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

- (id)initWithPrivateKey:(NSString *)privateKey
{
    if (! [self init]) return nil;
    
    self.privateKey = privateKey;
    
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

- (NSData *)publicKey
{
    std::vector<unsigned char>raw = _key->GetPubKey().Raw();
    
    [NSData dataWithBytes:&raw[0] length:raw.size()];
    
    return nil;
}

- (NSString *)address
{
    CKeyID keyID = _key->GetPubKey().GetID();
    std::vector<unsigned char>vch(1, 0x00);

    vch.insert(vch.end(), (unsigned char *)&keyID, (unsigned char *)&keyID + 20);
    
    return [NSString stringWithUTF8String:EncodeBase58Check(vch).c_str()];
}

- (NSData *)sign:(NSData *)d
{
    std::vector<unsigned char>sig;

    if (d.length != 256/8) {
        NSLog(@"Only sign 256bit hashes can be signed");
        return nil;
    }

    _key->Sign(Hash((unsigned char *)d.bytes, (unsigned char *)d.bytes + d.length), sig);

    return [NSData dataWithBytes:&sig[0] length:sig.size()];
}

@end

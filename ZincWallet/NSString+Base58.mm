//
//  NSString+Base58.mm
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "NSString+Base58.h"

#include "base58.h"
#include "ui_interface.h"

CClientUIInterface uiInterface; // hack to avoid having to build and link bitcoin/src/init.cpp

@implementation NSString (Base58)

+ (NSString *)base58checkWithData:(NSData *)d
{
    std::vector<unsigned char>v((unsigned char *)d.bytes, (unsigned char *)d.bytes + d.length);

    return [NSString stringWithUTF8String:EncodeBase58Check(v).c_str()];
}

- (NSString *)hexToBase58check
{
    return [NSString stringWithUTF8String:EncodeBase58Check(ParseHex(self.UTF8String)).c_str()];
}

- (NSString *)base58checkToHex
{
    std::vector<unsigned char>v;

    if (! DecodeBase58Check(self.UTF8String, v)) return nil;

    return [NSString stringWithUTF8String:HexStr(v).c_str()];
}

- (NSData *)base58checkToData
{
    std::vector<unsigned char>v;
    
    if (! DecodeBase58Check(self.UTF8String, v)) return nil;
    
    return [NSData dataWithBytes:&v[0] length:v.size()];
}

- (BOOL)isValidBitcoinAddress
{
    return CBitcoinAddress(self.UTF8String).IsValid();
}

@end

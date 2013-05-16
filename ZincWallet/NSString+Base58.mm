//
//  NSString+Base58.mm
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "NSString+Base58.h"

#include "base58.h"

@implementation NSString (Base58)

- (NSString *)hexToBase58check
{
    return [NSString stringWithUTF8String:EncodeBase58Check(ParseHex(self.UTF8String)).c_str()];
}

- (NSString *)base58checkToHex
{
    std::vector<unsigned char>vchRet;

    if (! DecodeBase58Check(self.UTF8String, vchRet)) return nil;

    return [NSString stringWithUTF8String:HexStr(vchRet).c_str()];
}


@end

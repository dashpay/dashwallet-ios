//
//  NSString+Base58.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "NSString+Base58.h"
#import <CommonCrypto/CommonDigest.h>

const char base58chars[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

@implementation NSString (Base58)

- (NSString *)hexToBase58check
{
    if (self.length % 2) return nil; // sanity check

    const char *s = self.UTF8String;
    int l = self.length/2 + 5;
    uint8_t d[self.length/2 + 1 + CC_SHA256_DIGEST_LENGTH];
    
    d[0] = 0; // base58check version 
    
    for (int i = 0; i < self.length; i += 2) {
        d[i/2 + 1] = (s[i] - (s[i] > '9' ? 'a' : '0'))*16 + s[i + 1] - (s[i + 1] > '9' ? 'a' : '0');
    }
    
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    
    CC_SHA256(d, l - 4, hash);
    CC_SHA256(hash, CC_SHA256_DIGEST_LENGTH, d + l - 4); // hash check
    
    char b58[l*2 + 1];
    int j = l*2, z = 0;

    while (d[z] == 0) z++; // count leading nil bytes

    b58[j--] = '\0';
    
    while (j >= 0) {
        int r = 0, r2 = 0, x;
        for (int i = 0; i < l; i++) {
            x = r*(UINT8_MAX + 1) + d[i];
            r2 = x % 58;
            d[i] = x/58;
            r = r2;
        }
    
        b58[j--] = base58chars[r];
    }

    for (j = 0; b58[j] == '1'; j++);

    return [NSString stringWithUTF8String:b58 + j - z];
}

- (NSString *)base58checkToHex
{
    return nil;
}


@end

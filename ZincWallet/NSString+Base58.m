//
//  NSString+Base58.mm
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "NSString+Base58.h"
#import "NSData+Hash.h"
#import <openssl/bn.h>

const char base58chars[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

@implementation NSString (Base58)

+ (NSString *)base58WithData:(NSData *)d
{
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length*138/100 + 1];
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM base, x, r;
    unichar c;

    BN_init(&base);
    BN_init(&x);
    BN_init(&r);
    BN_set_word(&base, 58);
    BN_bin2bn((unsigned char *)d.bytes, d.length, &x);

    while (! BN_is_zero(&x)) {
        BN_div(&x, &r, &x, &base, ctx);
        c = base58chars[BN_get_word(&r)];
        [s insertString:[NSString stringWithCharacters:&c length:1] atIndex:0];
    }
    
    c = base58chars[0];

    for (NSUInteger i = 0; i < d.length && *((uint8_t *)d.bytes + i) == 0; i++) {
        [s insertString:[NSString stringWithCharacters:&c length:1] atIndex:0];
    }

    BN_clear_free(&r);
    BN_clear_free(&x);
    BN_free(&base);
    BN_CTX_free(ctx);
    
    return s;
}

+ (NSString *)base58checkWithData:(NSData *)d
{
    NSMutableData *data = [NSMutableData dataWithData:d];

    [data appendData:[[d SHA256_2] subdataWithRange:NSMakeRange(0, 4)]];
    
    return [NSString base58WithData:data];
}

- (NSMutableData *)base58ToData
{
    const char *s = [self UTF8String];
    NSMutableData *d = [NSMutableData dataWithCapacity:self.length*138/100 + 1];
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM base, x, a;
    
    BN_init(&base);
    BN_init(&x);
    BN_init(&a);
    BN_set_word(&base, 58);
    BN_zero(&x);
    
    for (NSUInteger i = 0; i < self.length && [self characterAtIndex:i] == base58chars[0]; i++) {
        [d appendBytes:"\0" length:1];
    }
        
    for (NSUInteger i = 0; i < self.length; i++) {
        unsigned int b = 0;
        switch (s[i]) {
            case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
                b = s[i] - '1';
                break;
            case 'A': case 'B': case 'C': case 'D': case 'E': case 'F': case 'G': case 'H':
                b = s[i] + 9 - 'A';
                break;
            case 'J': case 'L': case 'M': case 'N':
                b = s[i] + 17 - 'J';
                break;
            case 'P': case 'Q': case 'R': case 'S': case 'T': case 'U': case 'V': case 'W': case 'X': case 'Y':
            case 'Z':
                b = s[i] + 21 - 'P';
                break;
            case 'a': case 'b': case 'c': case 'd': case 'e': case 'f': case 'g': case 'h': case 'i': case 'j':
            case 'k': case 'l': case 'm': case 'n': case 'o': case 'p': case 'q': case 'r': case 's': case 't':
            case 'u': case 'v': case 'w': case 'x': case 'y': case 'z':
                b = s[i] + 32 - 'a';
                break;
            case ' ':
                continue;
            default:
                goto breakout;
        }
        
        BN_mul(&x, &x, &base, ctx);
        BN_set_word(&a, b);
        BN_add(&x, &x, &a);
    }
    
breakout:
    d.length += BN_num_bytes(&x);
    BN_bn2bin(&x, (unsigned char *)d.mutableBytes + d.length - BN_num_bytes(&x));
    
    BN_clear_free(&a);
    BN_clear_free(&x);
    BN_free(&base);
    BN_CTX_free(ctx);
    
    return d;
}

- (NSString *)hexToBase58
{
    return [NSString base58WithData:[NSData dataWithHex:self]];
}

- (NSString *)base58ToHex
{
    return [[self base58ToData] toHex];
}

- (NSMutableData *)base58checkToData
{
    NSMutableData *d = [self base58ToData];
    
    if (d.length < 4) return nil;

    NSData *data = [NSData dataWithBytesNoCopy:d.mutableBytes length:d.length - 4];
    NSData *check = [NSData dataWithBytesNoCopy:(unsigned char *)d.mutableBytes + d.length - 4 length:4];
    
    if (! [[[data SHA256_2] subdataWithRange:NSMakeRange(0, 4)] isEqualToData:check]) return nil;
    
    OPENSSL_cleanse((unsigned char *)d.mutableBytes + d.length - 4, 4);
    d.length -= 4;
    return d;
}

- (NSString *)hexToBase58check
{
    return [NSString base58checkWithData:[NSData dataWithHex:self]];
}

- (NSString *)base58checkToHex
{
    NSMutableData *d = [self base58checkToData];
    NSString *hex = [d toHex];

    OPENSSL_cleanse(d.mutableBytes, d.length);
    return hex;
}

- (BOOL)isValidBitcoinAddress
{
    NSMutableData *d = [self base58checkToData];
    BOOL r = NO;
    
    if (d.length == 21) {
        switch (*(uint8_t *)d.bytes) {
            case BITCOIN_PUBKEY_ADDRESS:
            case BITCOIN_SCRIPT_ADDRESS:
                r = ! BITCOIN_TESTNET;
                break;
                
            case BITCOIN_PUBKEY_ADDRESS_TEST:
            case BITCOIN_SCRIPT_ADDRESS_TEST:
                r = BITCOIN_TESTNET;
                break;
        }
    }
    
    OPENSSL_cleanse(d.mutableBytes, d.length); // just because you're paranoid doesn't mean they're not out to get you!
    return r;
}

@end

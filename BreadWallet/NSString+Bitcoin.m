//
//  NSString+Bitcoin.m
//  BreadWallet
//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  base58 encoding/decoding based on libbase58, Copyright 2012-2014 Luke Dashjr
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

#import "NSString+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"
#import "ccMemory.h"
#include "string.h"

static const UniChar base58chars[] = {
    '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'm', 'n',
    'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
};

static const int8_t base58map[] = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1,  0,  1,  2,  3,  4,  5,  6,  7,  8, -1, -1, -1, -1, -1, -1,
    -1,  9, 10, 11, 12, 13, 14, 15, 16, -1, 17, 18, 19, 20, 21, -1,
    22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, -1, -1, -1, -1, -1,
    -1, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, -1, 44, 45, 46,
    47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, -1, -1, -1, -1, -1
};

@implementation NSString (Bitcoin)

+ (NSString *)base58WithData:(NSData *)d
{
    CFMutableStringRef s = CFStringCreateMutable(SecureAllocator(), d.length*138/100);
    const uint8_t *b = d.bytes;
    ssize_t i, j, high, carry, zcount = 0;
    
    while (zcount < d.length && b[zcount] == 0) CFStringAppendCharacters(s, base58chars, 1), zcount++; // leading zeroes
    
    uint8_t buf[(d.length - zcount)*138/100 + 1];

    CC_XZEROMEM(buf, sizeof(buf));
    
    for (i = zcount, high = sizeof(buf)/sizeof(*buf) - 1; i < d.length; i++, high = j) {
        for (carry = b[i], j = sizeof(buf)/sizeof(*buf) - 1; (j > high) || carry; j--) {
            carry += (uint32_t)buf[j] << 8;
            buf[j] = carry % 58;
            carry /= 58;
        }
    }
    
    for (i = 0; i < sizeof(buf)/sizeof(*buf) && buf[i] == 0; i++);
    while (i < sizeof(buf)/sizeof(*buf)) CFStringAppendCharacters(s, &base58chars[buf[i++]], 1);

    CC_XZEROMEM(buf, sizeof(buf));
    return CFBridgingRelease(s);
}

+ (NSString *)base58checkWithData:(NSData *)d
{
    NSMutableData *data = [NSMutableData secureDataWithData:d];

    [data appendBytes:d.SHA256_2.bytes length:4];
    return [self base58WithData:data];
}

+ (NSString *)hexWithData:(NSData *)d
{
    const uint8_t *bytes = d.bytes;
    NSMutableString *hex = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), d.length*2));
    
    for (NSUInteger i = 0; i < d.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    
    return hex;
}

// NOTE: It's important here to be permissive with scriptSig (spends) and strict with scriptPubKey (receives). If we
// miss a receive transaction, only that transaction's funds are missed, however if we accept a receive transaction that
// we are unable to correctly sign later, then the entire wallet balance after that point would become stuck with the
// current coin selection code
+ (NSString *)addressWithScriptPubKey:(NSData *)script
{
    if (script == (id)[NSNull null]) return nil;

    NSArray *elem = [script scriptElements];
    NSUInteger l = elem.count;
    NSMutableData *d = [NSMutableData data];
    uint8_t v = BITCOIN_PUBKEY_ADDRESS;

#if BITCOIN_TESTNET
    v = BITCOIN_PUBKEY_ADDRESS_TEST;
#endif

    if (l == 5 && [elem[0] intValue] == OP_DUP && [elem[1] intValue] == OP_HASH160 && [elem[2] intValue] == 20 &&
        [elem[3] intValue] == OP_EQUALVERIFY && [elem[4] intValue] == OP_CHECKSIG) {
        // pay-to-pubkey-hash scriptPubKey
        [d appendBytes:&v length:1];
        [d appendData:elem[2]];
    }
    else if (l == 3 && [elem[0] intValue] == OP_HASH160 && [elem[1] intValue] == 20 && [elem[2] intValue] == OP_EQUAL) {
        // pay-to-script-hash scriptPubKey
        v = BITCOIN_SCRIPT_ADDRESS;
#if BITCOIN_TESTNET
        v = BITCOIN_SCRIPT_ADDRESS_TEST;
#endif
        [d appendBytes:&v length:1];
        [d appendData:elem[1]];
    }
    else if (l == 2 && ([elem[0] intValue] == 65 || [elem[0] intValue] == 33) && [elem[1] intValue] == OP_CHECKSIG) {
        // pay-to-pubkey scriptPubKey
        [d appendBytes:&v length:1];
        [d appendData:[elem[0] hash160]];
    }
    else return nil; // unknown script type

    return [self base58checkWithData:d];
}

+ (NSString *)addressWithScriptSig:(NSData *)script
{
    if (script == (id)[NSNull null]) return nil;

    NSArray *elem = [script scriptElements];
    NSUInteger l = elem.count;
    NSMutableData *d = [NSMutableData data];
    uint8_t v = BITCOIN_PUBKEY_ADDRESS;

#if BITCOIN_TESTNET
    v = BITCOIN_PUBKEY_ADDRESS_TEST;
#endif

    if (l >= 2 && [elem[l - 2] intValue] <= OP_PUSHDATA4 && [elem[l - 2] intValue] > 0 &&
        ([elem[l - 1] intValue] == 65 || [elem[l - 1] intValue] == 33)) { // pay-to-pubkey-hash scriptSig
        [d appendBytes:&v length:1];
        [d appendData:[elem[l - 1] hash160]];
    }
    else if (l >= 2 && [elem[l - 2] intValue] <= OP_PUSHDATA4 && [elem[l - 2] intValue] > 0 &&
             [elem[l - 1] intValue] <= OP_PUSHDATA4 && [elem[l - 1] intValue] > 0) { // pay-to-script-hash scriptSig
        v = BITCOIN_SCRIPT_ADDRESS;
#if BITCOIN_TESTNET
        v = BITCOIN_SCRIPT_ADDRESS_TEST;
#endif
        [d appendBytes:&v length:1];
        [d appendData:[elem[l - 1] hash160]];
    }
    else if (l >= 1 && [elem[l - 1] intValue] <= OP_PUSHDATA4 && [elem[l - 1] intValue] > 0) {// pay-to-pubkey scriptSig
        //TODO: implement Peter Wullie's pubKey recovery from signature
        return nil;
    }
    else return nil; // unknown script type
    
    return [self base58checkWithData:d];
}

- (NSData *)base58ToData
{
    NSMutableData *d = [NSMutableData secureDataWithCapacity:self.length];
    size_t i, j, zcount = 0;

    while (zcount < self.length && [self characterAtIndex:zcount] == *base58chars) zcount++; // count leading zeroes

    uint32_t buf[((self.length - zcount)*100/136)/4 + 1], c;
    uint64_t t;

    CC_XZEROMEM(buf, sizeof(buf));
    
    for (i = zcount; i < self.length; i++) {
        c = [self characterAtIndex:i];
        if (c >= sizeof(base58map)/sizeof(*base58map) || base58map[c] == -1) return nil; // not a base58 digit
        c = (uint32_t)base58map[c];

        for (j = sizeof(buf)/sizeof(*buf); j--;) {
            t = ((uint64_t)buf[j])*58 + c;
            c = (t & 0x3f00000000ULL) >> 32;
            buf[j] = t & 0xffffffffu;
        }
    }
    
    for (i = 0; i < sizeof(buf)/sizeof(*buf); i++) buf[i] = CFSwapInt32HostToBig(buf[i]);
    for (i = 0; i < sizeof(buf) && ((unsigned char *)buf)[i] == 0; i++);
    d.length = zcount;
    [d appendBytes:&((unsigned char *)buf)[i] length:sizeof(buf) - i];

    CC_XZEROMEM(buf, sizeof(buf));
    return d;
}

- (NSString *)hexToBase58
{
    return [[self class] base58WithData:self.hexToData];
}

- (NSString *)base58ToHex
{
    return [NSString hexWithData:self.base58ToData];
}

- (NSData *)base58checkToData
{
    NSData *d = self.base58ToData;
    
    if (d.length < 4) return nil;

    NSData *data = CFBridgingRelease(CFDataCreate(SecureAllocator(), d.bytes, d.length - 4));

    // verify checksum
    if (*(uint32_t *)((const uint8_t *)d.bytes + d.length - 4) != *(uint32_t *)data.SHA256_2.bytes) return nil;
    return data;
}

- (NSString *)hexToBase58check
{
    return [NSString base58checkWithData:self.hexToData];
}

- (NSString *)base58checkToHex
{
    return [NSString hexWithData:self.base58checkToData];
}

- (NSData *)hexToData
{
    if (self.length % 2) return nil;
    
    NSMutableData *d = [NSMutableData secureDataWithCapacity:self.length/2];
    uint8_t b = 0;
    
    for (NSUInteger i = 0; i < self.length; i++) {
        unichar c = [self characterAtIndex:i];
        
        switch (c) {
            case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
                b += c - '0';
                break;
            case 'A': case 'B': case 'C': case 'D': case 'E': case 'F':
                b += c + 10 - 'A';
                break;
            case 'a': case 'b': case 'c': case 'd': case 'e': case 'f':
                b += c + 10 - 'a';
                break;
            default:
                return d;
        }
        
        if (i % 2) {
            [d appendBytes:&b length:1];
            b = 0;
        }
        else b *= 16;
    }
    
    return d;
}

- (NSData *)addressToHash160
{
    NSData *d = self.base58checkToData;

    return (d.length == 160/8 + 1) ? [d subdataWithRange:NSMakeRange(1, d.length - 1)] : nil;
}

- (BOOL)isValidBitcoinAddress
{
    NSData *d = self.base58checkToData;
    
    if (d.length != 21) return NO;
    
    uint8_t version = *(const uint8_t *)d.bytes;
        
#if BITCOIN_TESTNET
    return (version == BITCOIN_PUBKEY_ADDRESS_TEST || version == BITCOIN_SCRIPT_ADDRESS_TEST) ? YES : NO;
#endif

    return (version == BITCOIN_PUBKEY_ADDRESS || version == BITCOIN_SCRIPT_ADDRESS) ? YES : NO;
}

- (BOOL)isValidBitcoinPrivateKey
{
    NSData *d = self.base58checkToData;
    
    if (d.length == 33 || d.length == 34) { // wallet import format: https://en.bitcoin.it/wiki/Wallet_import_format
#if BITCOIN_TESNET
        return (*(const uint8_t *)d.bytes == BITCOIN_PRIVKEY_TEST) ? YES : NO;
#else
        return (*(const uint8_t *)d.bytes == BITCOIN_PRIVKEY) ? YES : NO;
#endif
    }
    else if ((self.length == 30 || self.length == 22) && [self characterAtIndex:0] == 'S') { // mini private key format
        NSMutableData *d = [NSMutableData secureDataWithCapacity:self.length + 1];

        d.length = self.length;
        [self getBytes:d.mutableBytes maxLength:d.length usedLength:NULL encoding:NSUTF8StringEncoding options:0
         range:NSMakeRange(0, self.length) remainingRange:NULL];
        [d appendBytes:"?" length:1];
        return (*(const uint8_t *)d.SHA256.bytes == 0) ? YES : NO;
    }
    else return (self.hexToData.length == 32) ? YES : NO; // hex encoded key
}

// BIP38 encrypted keys: https://github.com/bitcoin/bips/blob/master/bip-0038.mediawiki
- (BOOL)isValidBitcoinBIP38Key
{
    NSData *d = self.base58checkToData;

    if (d.length != 39) return NO; // invalid length

    uint16_t prefix = CFSwapInt16BigToHost(*(const uint16_t *)d.bytes);
    uint8_t flag = ((const uint8_t *)d.bytes)[2];

    if (prefix == BIP38_NOEC_PREFIX) { // non EC multiplied key
        return ((flag & BIP38_NOEC_FLAG) == BIP38_NOEC_FLAG && (flag & BIP38_LOTSEQUENCE_FLAG) == 0 &&
                (flag & BIP38_INVALID_FLAG) == 0) ? YES : NO;
    }
    else if (prefix == BIP38_EC_PREFIX) { // EC multiplied key
        return ((flag & BIP38_NOEC_FLAG) == 0 && (flag & BIP38_INVALID_FLAG) == 0) ? YES : NO;
    }
    else return NO; // invalid prefix
}

@end

//
//  ZNBIP39Mnemonic.m
//  ZincWallet
//
//  Created by Aaron Voisine on 3/21/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
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

#import "ZNBIP39Mnemonic.h"
#import "ZNKeySequence.h"
#import "NSString+Base58.h"
#import "NSData+Hash.h"
#import "NSMutableData+Bitcoin.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#import <openssl/crypto.h>

#define WORDS @"BIP39EnglishWords"

// BIP39 is method for generating a determinist wallet seed from a mnemonic phrase
// https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki

@implementation ZNBIP39Mnemonic

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;

    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });

    return singleton;
}

- (NSString *)encodePhrase:(NSData *)data
{
    if ((data.length % 4) != 0) return nil; // data length must be a multiple of 32 bits

    NSArray *words = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:WORDS ofType:@"plist"]];
    uint32_t n = (uint32_t)words.count, x;
    NSMutableArray *a =
        CFBridgingRelease(CFArrayCreateMutable(SecureAllocator(), data.length*3/4, &kCFTypeArrayCallBacks));
    NSMutableData *d = [NSMutableData secureDataWithData:data];

    [d appendData:data.SHA256]; // append SHA256 checksum

    for (int i = 0; i < data.length*3/4; i++) {
        x = CFSwapInt32BigToHost(*(uint32_t *)((uint8_t *)d.bytes + i*11/8));
        [a addObject:words[(x >> (sizeof(x)*8 - (11 + ((i*11) % 8)))) % n]];
    }

    x = 0;
    return CFBridgingRelease(CFStringCreateByCombiningStrings(SecureAllocator(), (__bridge CFArrayRef)a, CFSTR(" ")));
}

- (NSData *)decodePhrase:(NSString *)phrase
{
    CFMutableStringRef s = CFStringCreateMutableCopy(SecureAllocator(), phrase.length, (__bridge CFStringRef)phrase);

    CFStringLowercase(s, CFLocaleGetSystem());
    CFStringFindAndReplace(s, CFSTR("."), CFSTR(" "), CFRangeMake(0, CFStringGetLength(s)), 0);
    CFStringFindAndReplace(s, CFSTR(","), CFSTR(" "), CFRangeMake(0, CFStringGetLength(s)), 0);
    CFStringFindAndReplace(s, CFSTR("\n"), CFSTR(" "), CFRangeMake(0, CFStringGetLength(s)), 0);
    CFStringTrimWhitespace(s);
    while (CFStringFindAndReplace(s, CFSTR("  "), CFSTR(" "), CFRangeMake(0, CFStringGetLength(s)), 0) != 0);

    NSArray *words = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:WORDS ofType:@"plist"]];
    NSArray *a = CFBridgingRelease(CFStringCreateArrayBySeparatingStrings(SecureAllocator(), s, CFSTR(" ")));
    NSMutableData *d = [NSMutableData secureDataWithCapacity:(a.count*11 + 7)/8];
    uint32_t n = (int32_t)words.count, x, y;
    uint8_t b;

    CFRelease(s);

    if ((a.count % 3) != 0 || a.count > 24) {
        NSLog(@"phrase has wrong number of words");
        return nil;
    }

    for (int i = 0; i < (a.count*11 + 7)/8; i++) {
        x = [words indexOfObject:a[i*8/11]];
        y = (i*8/11 + 1 < a.count) ? [words indexOfObject:a[i*8/11 + 1]] : 0;

        if (x == NSNotFound || y == NSNotFound) {
            NSLog(@"phrase contained unknown word: %@", a[i*8/11 + (x == NSNotFound ? 0 : 1)]);
            return nil;
        }

        b = ((x*n + y) >> ((i*8/11 + 2)*11 - (i + 1)*8)) & 0xff;
        [d appendBytes:&b length:1];
    }

    b = *((uint8_t *)d.bytes + a.count*4/3) >> (8 - a.count/3);
    d.length = a.count*4/3;

    if (b != (*(uint8_t *)d.SHA256.bytes >> (8 - a.count/3))) {
        NSLog(@"incorrect phrase, bad checksum");
        return nil;
    }

    x = y = b = 0;
    return d;
}

- (BOOL)phraseIsValid:(NSString *)phrase
{
    return ([self decodePhrase:phrase] == nil) ? NO : YES;
}

- (NSData *)deriveKeyFromPhrase:(NSString *)phrase withPassphrase:(NSString *)passphrase
{
    NSMutableData *key = [NSMutableData secureDataWithLength:CC_SHA512_DIGEST_LENGTH];
    CFMutableStringRef str = CFStringCreateMutableCopy(SecureAllocator(), phrase.length, (__bridge CFStringRef)phrase);
    CFMutableStringRef salt = CFStringCreateMutableCopy(SecureAllocator(), 8 + passphrase.length, CFSTR("mnemonic"));

    if (passphrase) CFStringAppend(salt, (__bridge CFStringRef)passphrase);
    CFStringNormalize(str, kCFStringNormalizationFormKD);
    CFStringNormalize(salt, kCFStringNormalizationFormKD);

    char strbuf[CFStringGetMaximumSizeForEncoding(CFStringGetLength(str), kCFStringEncodingUTF8)];
    char saltbuf[CFStringGetMaximumSizeForEncoding(CFStringGetLength(salt), kCFStringEncodingUTF8)];
    const char *strptr = CFStringGetCStringPtr(str, kCFStringEncodingUTF8);
    const char *saltptr = CFStringGetCStringPtr(salt, kCFStringEncodingUTF8);

    if (strptr == NULL && CFStringGetCString(str, strbuf, sizeof(strbuf), kCFStringEncodingUTF8)) strptr = strbuf;
    if (saltptr == NULL && CFStringGetCString(salt, saltbuf, sizeof(saltbuf), kCFStringEncodingUTF8)) saltptr = saltbuf;

    CCKeyDerivationPBKDF(kCCPBKDF2, strptr, strlen(strptr), (const uint8_t *)saltptr, strlen(saltptr),
                         kCCPRFHmacAlgSHA512, 2048, key.mutableBytes, key.length);

    OPENSSL_cleanse(strbuf, sizeof(strbuf));
    OPENSSL_cleanse(saltbuf, sizeof(saltbuf));
    CFRelease(str);
    CFRelease(salt);

    return key;
}

@end

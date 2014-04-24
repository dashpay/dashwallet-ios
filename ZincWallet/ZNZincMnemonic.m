//
//  ZNZincMnemonic.m
//  ZincWallet
//
//  Created by Aaron Voisine on 8/15/13.
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

#import "ZNZincMnemonic.h"
#import "ZNKeySequence.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import <openssl/crypto.h>

#define ADJS  @"MnemonicAdjs"
#define NOUNS @"MnemonicNouns"
#define ADVS  @"MnemonicAdvs"
#define VERBS @"MnemonicVerbs"

#define SEED_LENGTH (128/8)

@implementation ZNZincMnemonic

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
    if (data.length != SEED_LENGTH) return nil;
    
    NSArray *adjs = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:ADJS ofType:@"plist"]];
    NSArray *nouns = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:NOUNS ofType:@"plist"]];
    NSArray *advs = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:ADVS ofType:@"plist"]];
    NSArray *verbs = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:VERBS ofType:@"plist"]];
    NSMutableArray *a =
        CFBridgingRelease(CFArrayCreateMutable(SecureAllocator(), data.length*3/4, &kCFTypeArrayCallBacks));
    NSMutableString *s = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), 0));
    NSUInteger x;
    const uint8_t *b = data.bytes;
    
    for (int i = 0; i < SEED_LENGTH; i += 64/8) {
        x = (((uint16_t)b[i] << 3) | ((uint16_t)b[i + 1] >> 5)) & ((1 << 11) - 1);
        [s setString:adjs[x]];
        CFStringCapitalize((CFMutableStringRef)s, CFLocaleGetSystem());
        [a addObject:CFBridgingRelease(CFStringCreateCopy(SecureAllocator(), (CFStringRef)s))];

        x = (((uint16_t)b[i + 1] << 6) | ((uint16_t)b[i + 2] >> 2)) & ((1 << 11) - 1);
        [a addObject:nouns[x]];

        x = (((uint16_t)b[i + 2] << 8) | (uint16_t)b[i + 3]) & ((1 << 10) - 1);
        [a addObject:advs[x]];

        x = (((uint16_t)b[i + 4] << 2) | (uint16_t)b[i + 5] >> 6) & ((1 << 10) - 1);
        [a addObject:verbs[x]];

        x = (((uint16_t)b[i + 5] << 5) | ((uint16_t)b[i + 6] >> 3)) & ((1 << 11) - 1);
        [a addObject:adjs[x]];

        x = (((uint16_t)b[i + 6] << 8) | (uint16_t)b[i + 7]) & ((1 << 11) - 1);
        [s setString:nouns[x]];
        [s appendString:@"."];
        [a addObject:CFBridgingRelease(CFStringCreateCopy(SecureAllocator(), (CFStringRef)s))];
    }

    OPENSSL_cleanse(&x, sizeof(x));
    return CFBridgingRelease(CFStringCreateByCombiningStrings(SecureAllocator(), (CFArrayRef)a, CFSTR(" ")));
}
 
- (NSData *)decodePhrase:(NSString *)phrase
{
    CFMutableStringRef s = CFStringCreateMutableCopy(SecureAllocator(), phrase.length, (CFStringRef)phrase);
    
    CFStringLowercase(s, CFLocaleGetSystem());
    CFStringFindAndReplace(s, CFSTR("."), CFSTR(" "), CFRangeMake(0, CFStringGetLength(s)), 0);
    CFStringFindAndReplace(s, CFSTR(","), CFSTR(" "), CFRangeMake(0, CFStringGetLength(s)), 0);
    CFStringFindAndReplace(s, CFSTR("\n"), CFSTR(" "), CFRangeMake(0, CFStringGetLength(s)), 0);
    CFStringTrimWhitespace(s);
    while (CFStringFindAndReplace(s, CFSTR("  "), CFSTR(" "), CFRangeMake(0, CFStringGetLength(s)), 0) != 0);

    NSArray *adjs = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:ADJS ofType:@"plist"]];
    NSArray *nouns = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:NOUNS ofType:@"plist"]];
    NSArray *advs = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:ADVS ofType:@"plist"]];
    NSArray *verbs = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:VERBS ofType:@"plist"]];
    NSArray *a = CFBridgingRelease(CFStringCreateArrayBySeparatingStrings(SecureAllocator(), s, CFSTR(" ")));
    NSMutableData *d = [NSMutableData secureDataWithCapacity:SEED_LENGTH];
    NSUInteger x, y;
    uint8_t b;

    CFRelease(s);

    if (a.count != SEED_LENGTH*3/4) return nil;

    for (int i = 0; i < SEED_LENGTH*3/4; i += 6) {
        if ((x = [adjs indexOfObject:a[i]]) == NSNotFound) return nil;
        b = (x >> 3) & 0xff;
        [d appendBytes:&b length:1];
        
        if ((y = [nouns indexOfObject:a[i + 1]]) == NSNotFound) return nil;
        b = ((x << 5) | (y >> 6)) & 0xff;
        [d appendBytes:&b length:1];
        
        if ((x = [advs indexOfObject:a[i + 2]]) == NSNotFound) return nil;
        b = ((y << 2) | (x >> 8)) & 0xff;
        [d appendBytes:&b length:1];
        b = x & 0xff;
        [d appendBytes:&b length:1];

        if ((y = [verbs indexOfObject:a[i + 3]]) == NSNotFound) return nil;
        b = (y >> 2) & 0xff;
        [d appendBytes:&b length:1];
        
        if ((x = [adjs indexOfObject:a[i + 4]]) == NSNotFound) return nil;
        b = ((y << 6) | (x >> 5)) & 0xff;
        [d appendBytes:&b length:1];
        
        if ((y = [nouns indexOfObject:a[i + 5]]) == NSNotFound) return nil;
        b = ((x << 3) | (y >> 8)) & 0xff;
        [d appendBytes:&b length:1];
        b = y & 0xff;
        [d appendBytes:&b length:1];
    }

    OPENSSL_cleanse(&x, sizeof(x));
    OPENSSL_cleanse(&y, sizeof(y));
    OPENSSL_cleanse(&b, sizeof(b));
    return d;
}

- (BOOL)phraseIsValid:(NSString *)phrase
{
    return ([self decodePhrase:phrase] == nil) ? NO : YES;
}

@end

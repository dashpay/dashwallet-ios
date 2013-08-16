//
//  ZNBIP39Mnemonic.m
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

#import "ZNBIP39Mnemonic.h"
#import "NSString+Base58.h"

#define ADJS  @"BIP39-adjs"
#define NOUNS @"BIP39-nouns"
#define ADVS  @"BIP39-advs"
#define VERBS @"BIP39-verbs"

@implementation ZNBIP39Mnemonic

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{ singleton = [self new]; });
    return singleton;
}

- (NSString *)encodePhrase:(NSData *)data
{
    if (data.length != 128/8) return nil;
    
    NSArray *adj = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:ADJS ofType:@"plist"]];
    NSArray *noun = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:NOUNS ofType:@"plist"]];
    NSArray *adv = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:ADVS ofType:@"plist"]];
    NSArray *verb = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:VERBS ofType:@"plist"]];
    NSMutableArray *a =
        CFBridgingRelease(CFArrayCreateMutable(SecureAllocator(), data.length*3/4, &kCFTypeArrayCallBacks));
    uint8_t *b = (uint8_t *)data.bytes;
    uint16_t i;
    
    for (int j = 0; j < 128/8; j += 64/8) {
        i = ((b[j] << 3) | (b[j + 1] >> 5)) & ((1 << 11) - 1);
        [a addObject:adj[i]];

        i = ((b[j + 1] << 6) | (b[j + 2] >> 2)) & ((1 << 11) - 1);
        [a addObject:noun[i]];

        i = ((b[j + 2] << 8) | b[j + 3]) & ((1 << 10) - 1);
        [a addObject:adv[i]];

        i = ((b[j + 4] << 2) | b[j + 5] >> 6) & ((1 << 10) - 1);
        [a addObject:verb[i]];

        i = ((b[j + 5] << 5) | (b[j + 6] >> 3)) & ((1 << 11) - 1);
        [a addObject:adj[i]];

        i = ((b[j + 7] << 8) | b[j + 7]) & ((1 << 11) - 1);
        [a addObject:noun[i]];
    }
    
    return CFBridgingRelease(CFStringCreateByCombiningStrings(SecureAllocator(), (__bridge CFArrayRef)a, CFSTR(" ")));
}
 
- (NSData *)decodePhrase:(NSString *)phrase
{
    NSArray *adj = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:ADJS ofType:@"plist"]];
    NSArray *noun = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:NOUNS ofType:@"plist"]];
    NSArray *adv = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:ADVS ofType:@"plist"]];
    NSArray *verb = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:VERBS ofType:@"plist"]];
    CFMutableStringRef s = CFStringCreateMutableCopy(SecureAllocator(), phrase.length, (__bridge CFStringRef)phrase);
    
    CFStringTrimWhitespace(s);
    
    NSArray *a = CFBridgingRelease(CFStringCreateArrayBySeparatingStrings(SecureAllocator(), s, CFSTR(" ")));
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), 128/8));
    NSUInteger i;
    uint8_t b;
    
    if (a.count != 12) return nil;

    for (int j = 0; j < 12; j += 6) {
        if ((i = [adj indexOfObject:a[j]]) == NSNotFound) return nil;
        b = i >> 3;
        [d appendBytes:&b length:1];

        b = i << 5;
        if ((i = [noun indexOfObject:a[j + 1]]) == NSNotFound) return nil;
        b |= i >> 6;
        [d appendBytes:&b length:1];

        b = i << 2;
        if ((i = [adv indexOfObject:a[j + 2]]) == NSNotFound) return nil;
        b |= i >> 8;
        [d appendBytes:&b length:1];

        b = i;
        [d appendBytes:&b length:1];

        if ((i == [verb indexOfObject:a[j + 3]]) == NSNotFound) return nil;
        b = i >> 2;
        [d appendBytes:&b length:1];

        b = i << 6;
        if ((i == [adj indexOfObject:a[j + 4]]) == NSNotFound) return nil;
        b |= i >> 5;
        [d appendBytes:&b length:1];

        b = i << 3;
        if ((i == [noun indexOfObject:a[j + 5]]) == NSNotFound) return nil;
        b |= i >> 8;
        [d appendBytes:&b length:1];

        b = i;
        [d appendBytes:&b length:1];
    }
        
    return d;
}

@end

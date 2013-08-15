//
//  ZNElecturmMnemonic.m
//  ZincWallet
//
//  Created by Aaron Voisine on 7/19/13.
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

#import "ZNElecturmMnemonic.h"
#import "NSString+Base58.h"

@interface ZNElecturmMnemonic ()

@property (nonatomic, strong) NSArray *words;

@end

@implementation ZNElecturmMnemonic

+ (instancetype)mnemonicWithWords:(NSArray *)words
{
    return [[self alloc] initWithWords:words];
}

+ (instancetype)mnemonicWithWordPlist:(NSString *)plist
{
    return [[self alloc] initWithWordPlist:plist];
}

- (instancetype)initWithWords:(NSArray *)words
{
    if (! (self = [self init])) return nil;

    self.words = words;

    return self;
}

- (instancetype)initWithWordPlist:(NSString *)plist
{
    NSArray *words = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:plist ofType:@"plist"]];

    return [self initWithWords:words];
}

//# Note about US patent no 5892470: Here each word does not represent a given digit.
//# Instead, the digit represented by a word is variable, it depends on the previous word.
//
//def mn_encode( message ):
//    out = []
//    for i in range(len(message)/8):
//        word = message[8*i:8*i + 8]
//        x = int(word, 16)
//        w1 = (x % n)
//        w2 = ((x/n) + w1) % n
//        w3 = ((x/n/n) + w2) % n
//        out += [ words[w1], words[w2], words[w3] ]
//    return out
//
- (NSString *)encodePhrase:(NSData *)data
{
    uint32_t n = self.words.count, x, w1, w2, w3;
    NSMutableArray *list =
        CFBridgingRelease(CFArrayCreateMutable(SecureAllocator(), data.length*3/4, &kCFTypeArrayCallBacks));

    for (int i = 0; i*sizeof(uint32_t) < data.length; i++) {
        x = CFSwapInt32BigToHost(*((uint32_t *)data.bytes + i));
        w1 = x % n;
        w2 = ((x/n) + w1) % n;
        w3 = ((x/n/n) + w2) % n;

        [list addObject:self.words[w1]];
        [list addObject:self.words[w2]];
        [list addObject:self.words[w3]];
    }

    x = w1 = w2 = w3 = 0;
    return CFBridgingRelease(CFStringCreateByCombiningStrings(SecureAllocator(), (__bridge CFArrayRef)list,CFSTR(" ")));
}

//def mn_decode( wlist ):
//    out = ''
//    for i in range(len(wlist)/3):
//        word1, word2, word3 = wlist[3*i:3*i + 3]
//        w1 =  words.index(word1)
//        w2 = (words.index(word2)) % n
//        w3 = (words.index(word3)) % n
//        x = w1 + n*((w2 - w1) % n) + n*n*((w3 - w2) % n)
//        out += '%08x'%x
//    return out
//
- (NSData *)decodePhrase:(NSString *)phrase
{
    CFMutableStringRef s = CFStringCreateMutableCopy(SecureAllocator(), phrase.length, (__bridge CFStringRef)phrase);

    CFStringTrimWhitespace(s);

    NSArray *list = CFBridgingRelease(CFStringCreateArrayBySeparatingStrings(SecureAllocator(), s, CFSTR(" ")));
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), list.count*4/3));
    int32_t n = self.words.count, x, w1, w2, w3;

    if (list.count != 12) {
        NSLog(@"phrase should be 12 words, found %d instead", list.count);
        return nil;
    }

    for (NSUInteger i = 0; i < list.count; i += 3) {
        w1 = [self.words indexOfObject:list[i]];
        w2 = [self.words indexOfObject:list[i + 1]];
        w3 = [self.words indexOfObject:list[i + 2]];

        if (w1 == NSNotFound || w2 == NSNotFound || w3 == NSNotFound) {
            NSLog(@"phrase contained unknown word: %@", list[i + (w1 == NSNotFound ? 0 : w2 == NSNotFound ? 1 : 2)]);
            return nil;
        }

        // python's modulo behaves differently than C's when dealing with negative numbers
        // the equivalent of python's (n % M) in C is (((n % M) + M) % M)
        x = CFSwapInt32HostToBig(w1 + n*((((w2 - w1) % n) + n) % n) + n*n*((((w3 - w2) % n) + n) % n));
        
        [d appendBytes:&x length:sizeof(x)];
    }
    
    x = w1 = w2 = w3 = 0;
    return d;
}


@end

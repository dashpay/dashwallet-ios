//
//  ZNMnemonic.m
//  ZincWallet
//
//  Created by Administrator on 7/19/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNMnemonic.h"

@interface ZNMnemonic ()
    @property (nonatomic, strong) NSArray *words;
@end

@implementation ZNMnemonic

+ (ZNMnemonic *)mnemonicWithWords:(NSArray *)words
{
    return [[self alloc] initWithWords:words];
}

+ (ZNMnemonic *)mnemonicWithWordPlist:(NSString *)plist
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
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:data.length*3/4];
    uint32_t n = self.words.count;

    for (int i = 0; i*sizeof(uint32_t) < data.length; i++) {
        uint32_t x = CFSwapInt32BigToHost(*((uint32_t *)data.bytes + i));
        uint32_t w1 = x % n;
        uint32_t w2 = ((x/n) + w1) % n;
        uint32_t w3 = ((x/n/n) + w2) % n;

        [list addObject:self.words[w1]];
        [list addObject:self.words[w2]];
        [list addObject:self.words[w3]];
    }

    return [list componentsJoinedByString:@" "];
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
    NSArray *list = [phrase componentsSeparatedByString:@" "];
    NSMutableData *d = [NSMutableData dataWithCapacity:list.count*4/3];
    int32_t n = self.words.count;

    if (list.count != 12) {
        NSLog(@"phrase should be 12 words, found %d instead", list.count);
        return nil;
    }

    for (NSUInteger i = 0; i < list.count; i += 3) {
        int32_t w1 = [self.words indexOfObject:list[i]], w2 = [self.words indexOfObject:list[i + 1]],
        w3 = [self.words indexOfObject:list[i + 2]];

        if (w1 == NSNotFound || w2 == NSNotFound || w3 == NSNotFound) {
            NSLog(@"phrase contained unknown word: %@", list[i + (w1 == NSNotFound ? 0 : w2 == NSNotFound ? 1 : 2)]);
            return nil;
        }

        // python's modulo behaves differently than C when dealing with negative numbers
        // the equivalent of python's (n % M) in C is (((n % M) + M) % M)
        int32_t x = w1 + n*((((w2 - w1) % n) + n) % n) + n*n*((((w3 - w2) % n) + n) % n);

        x = CFSwapInt32HostToBig(x);
        
        [d appendBytes:&x length:sizeof(x)];
    }
    
    return d;
}


@end

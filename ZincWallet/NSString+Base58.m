//
//  NSString+Base58.mm
//  ZincWallet
//
//  Created by Aaron Voisine on 5/13/13.
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

#import "NSString+Base58.h"
#import "NSData+Hash.h"
#import <openssl/bn.h>

#define SCRIPT_SUFFIX "\x88\xAC" // OP_EQUALVERIFY OP_CHECKSIG

const char base58chars[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

static void *secureAllocate(CFIndex allocSize, CFOptionFlags hint, void *info)
{
    void *ptr = CFAllocatorAllocate(kCFAllocatorDefault, sizeof(CFIndex) + allocSize, hint);
    
    if (ptr) { // we need to keep track of the size of the allocation so it can be cleansed before deallocation
        *(CFIndex *)ptr = allocSize;
        return (CFIndex *)ptr + 1;
    }
    else return NULL;
}

static void secureDeallocate(void *ptr, void *info)
{
    CFIndex size = *((CFIndex *)ptr - 1);

    if (size) {
        OPENSSL_cleanse(ptr, size);
        CFAllocatorDeallocate(kCFAllocatorDefault, (CFIndex *)ptr - 1);
    }
}

static void *secureReallocate(void *ptr, CFIndex newsize, CFOptionFlags hint, void *info)
{
    // There's no way to tell ahead of time if the original memory will be deallocted even if the new size is smaller
    // than the old size, so just cleanse and deallocate every time.
    void *newptr = secureAllocate(newsize, hint, info);
    CFIndex size = *((CFIndex *)ptr - 1);

    if (newptr) {
        if (size) {
            memcpy(newptr, ptr, size < newsize ? size : newsize);
            secureDeallocate(ptr, info);
        }

        return newptr;
    }
    else return NULL;
}

// Since iOS does not page memory to storage, all we need to do is cleanse allocated memory prior to deallocation.
CFAllocatorRef SecureAllocator()
{
    static CFAllocatorRef alloc = NULL;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        CFAllocatorContext context;
        
        context.version = 0;
        CFAllocatorGetContext(kCFAllocatorDefault, &context);
        context.allocate = secureAllocate;
        context.reallocate = secureReallocate;
        context.deallocate = secureDeallocate;
        
        alloc = CFAllocatorCreate(kCFAllocatorDefault, &context);
    });
    
    return alloc;
}

@implementation NSString (Base58)

+ (NSString *)base58WithData:(NSData *)d
{
    NSUInteger i = d.length*138/100 + 2;
    char s[i];
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM base, x, r;

    BN_init(&base);
    BN_init(&x);
    BN_init(&r);
    BN_set_word(&base, 58);
    BN_bin2bn(d.bytes, (int)d.length, &x);
    s[--i] = '\0';

    while (! BN_is_zero(&x)) {
        BN_div(&x, &r, &x, &base, ctx);
        s[--i] = base58chars[BN_get_word(&r)];
    }
    
    for (NSUInteger j = 0; j < d.length && *((uint8_t *)d.bytes + j) == 0; j++) {
        s[--i] = base58chars[0];
    }

    BN_clear_free(&r);
    BN_clear_free(&x);
    BN_free(&base);
    BN_CTX_free(ctx);
    
    NSString *ret = CFBridgingRelease(CFStringCreateWithCString(SecureAllocator(), &s[i], kCFStringEncodingUTF8));
    
    OPENSSL_cleanse(&s[0], d.length*138/100 + 2);
    return ret;
}

+ (NSString *)base58checkWithData:(NSData *)d
{
    NSMutableData *data =
        CFBridgingRelease(CFDataCreateMutableCopy(SecureAllocator(), d.length + 4, (__bridge CFDataRef)d));

    [data appendBytes:d.SHA256_2.bytes length:4];
    
    return [self base58WithData:data];
}

- (NSData *)base58ToData
{
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), self.length*138/100 + 1));
    unsigned int b;
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM base, x, y;
    
    BN_init(&base);
    BN_init(&x);
    BN_init(&y);
    BN_set_word(&base, 58);
    BN_zero(&x);
    
    for (NSUInteger i = 0; i < self.length && [self characterAtIndex:i] == base58chars[0]; i++) {
        [d appendBytes:"\0" length:1];
    }
        
    for (NSUInteger i = 0; i < self.length; i++) {
        b = [self characterAtIndex:i];

        switch (b) {
            case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
                b -= '1';
                break;
            case 'A': case 'B': case 'C': case 'D': case 'E': case 'F': case 'G': case 'H':
                b += 9 - 'A';
                break;
            case 'J': case 'K': case 'L': case 'M': case 'N':
                b += 17 - 'J';
                break;
            case 'P': case 'Q': case 'R': case 'S': case 'T': case 'U': case 'V': case 'W': case 'X': case 'Y':
            case 'Z':
                b += 22 - 'P';
                break;
            case 'a': case 'b': case 'c': case 'd': case 'e': case 'f': case 'g': case 'h': case 'i': case 'j':
            case 'k':
                b += 33 - 'a';
                break;
            case 'm': case 'n': case 'o': case 'p': case 'q': case 'r': case 's': case 't': case 'u': case 'v':
            case 'w': case 'x': case 'y': case 'z':
                b += 44 - 'm';
                break;
            case ' ':
                continue;
            default:
                goto breakout;
        }
        
        BN_mul(&x, &x, &base, ctx);
        BN_set_word(&y, b);
        BN_add(&x, &x, &y);
    }
    
breakout:
    d.length += BN_num_bytes(&x);
    BN_bn2bin(&x, (unsigned char *)d.mutableBytes + d.length - BN_num_bytes(&x));

    b = 0;
    BN_clear_free(&y);
    BN_clear_free(&x);
    BN_free(&base);
    BN_CTX_free(ctx);
    
    return d;
}

+ (NSString *)hexWithData:(NSData *)d
{
    uint8_t *bytes = (uint8_t *)d.bytes;
    NSMutableString *hex = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), d.length*2));
    
    for (NSUInteger i = 0; i < d.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    
    return hex;
}

+ (NSString *)addressWithScript:(NSData *)script
{
    static NSData *suffix = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        suffix = [NSData dataWithBytes:SCRIPT_SUFFIX length:strlen(SCRIPT_SUFFIX)];
    });

    if (script == (id)[NSNull null] || script.length < suffix.length + 20 ||
        ! [[script subdataWithRange:NSMakeRange(script.length - suffix.length, suffix.length)] isEqualToData:suffix]) {
        return nil;
    }
    
#if BITCOIN_TESTNET
    uint8_t x = BITCOIN_PUBKEY_ADDRESS_TEST;
#else
    uint8_t x = BITCOIN_PUBKEY_ADDRESS;
#endif
    NSMutableData *d = [NSMutableData dataWithBytes:&x length:1];
    
    [d appendBytes:(const uint8_t *)script.bytes + script.length - suffix.length - 20 length:20];
    
    return [self base58checkWithData:d];
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
    
    if (memcmp((const unsigned char *)d.bytes + d.length - 4, data.SHA256_2.bytes, 4) != 0) return nil;
    
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
    
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), self.length/2));
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

- (BOOL)isValidBitcoinAddress
{
    NSData *d = self.base58checkToData;
    
    if (d.length != 21) return NO;
    
    uint8_t version = *(uint8_t *)d.bytes;
        
#if BITCOIN_TESTNET
    return (version == BITCOIN_PUBKEY_ADDRESS_TEST || version == BITCOIN_SCRIPT_ADDRESS_TEST) ? YES : NO;
#else
    return (version == BITCOIN_PUBKEY_ADDRESS || version == BITCOIN_SCRIPT_ADDRESS) ? YES : NO;
#endif
}

- (BOOL)isValidBitcoinPrivateKey
{
    NSData *d = self.base58checkToData;
    
    if (d.length == 33 || d.length == 34) {
#if BITCOIN_TESNET
        return (*(uint8_t *)d.bytes == BITCOIN_PRIVKEY_TEST) ? YES : NO;
#else
        return (*(uint8_t *)d.bytes == BITCOIN_PRIVKEY) ? YES : NO;
#endif
    }
    else if ((self.length == 30 || self.length == 22) && [self characterAtIndex:0] == 'S') { // mini private key format
        NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), self.length + 1));
        
        d.length = self.length;
        [self getBytes:d.mutableBytes maxLength:d.length usedLength:NULL encoding:NSUTF8StringEncoding options:0
         range:NSMakeRange(0, self.length) remainingRange:NULL];
        [d appendBytes:"?" length:1];
        return (*(uint8_t *)d.SHA256.bytes == 0) ? YES : NO;
    }
    else return NO;
}

@end

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

void *secureAllocate(CFIndex allocSize, CFOptionFlags hint, void *info)
{
    NSMutableDictionary *d = (__bridge NSMutableDictionary *)info;
    void *ptr = CFAllocatorAllocate(kCFAllocatorDefault, allocSize, hint);
    
    if (ptr) {
        [d setObject:[NSNumber numberWithUnsignedLong:allocSize] forKey:[NSValue valueWithPointer:ptr]];
        return ptr;
    }
    else return NULL;
}

void secureDeallocate(void *ptr, void *info)
{
    NSMutableDictionary *d = (__bridge NSMutableDictionary *)info;
    NSValue *key = [NSValue valueWithPointer:ptr];
    size_t size = [[d objectForKey:key] unsignedLongValue];
    
    if (size) {
        [d removeObjectForKey:key];
        OPENSSL_cleanse(ptr, size);
        CFAllocatorDeallocate(kCFAllocatorDefault, ptr);
    }
}

void *secureReallocate(void *ptr, CFIndex newsize, CFOptionFlags hint, void *info)
{
    // There's no way to tell ahead of time if there's enough space for the reallocation, or if the original memory
    // will be deallocted, so just cleanse and deallocate every time.
    NSMutableDictionary *d = (__bridge NSMutableDictionary *)info;
    void *newptr = secureAllocate(newsize, hint, info);
    
    if (newptr) {
        size_t size = [[d objectForKey:[NSValue valueWithPointer:ptr]] unsignedLongValue];
        
        if (size) {
            memcpy(newptr, ptr, size < newsize ? size : newsize);
            secureDeallocate(ptr, info);
            return newptr;
        }
        else {
            secureDeallocate(newptr, info);
            return NULL;
        }
    }
    else return NULL;
}

// Since iOS does not page memory to storage, all we need to do is cleanse allocated memory prior to deallocation.
CFAllocatorRef SecureAllocator()
{
    static CFAllocatorRef alloc = NULL;
    
    if (alloc == NULL) {
        CFAllocatorContext context;
        
        context.version = 0;
        CFAllocatorGetContext(kCFAllocatorDefault, &context);
        context.info = (void *)CFBridgingRetain([NSMutableDictionary dictionary]);
        context.allocate = secureAllocate;
        context.reallocate = secureReallocate;
        context.deallocate = secureDeallocate;
        
        alloc = CFAllocatorCreate(kCFAllocatorDefault, &context);
    }
    
    return alloc;
}

@implementation NSString (Base58)

+ (NSString *)base58WithData:(NSData *)d
{
    int i = d.length*138/100 + 2;
    char s[i];
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM base, x, r;

    BN_init(&base);
    BN_init(&x);
    BN_init(&r);
    BN_set_word(&base, 58);
    BN_bin2bn((unsigned char *)d.bytes, d.length, &x);
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
    NSMutableData *data = [NSMutableData dataWithData:d];

    [data appendData:[[d SHA256_2] subdataWithRange:NSMakeRange(0, 4)]];
    
    NSString *s = [self base58WithData:data];

    OPENSSL_cleanse(data.mutableBytes, d.length);
    return s;
}

- (NSData *)base58ToData
{
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), self.length*138/100 + 1));
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
        unsigned int b = [self characterAtIndex:i];

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

- (NSString *)hexToBase58
{
    NSMutableData *d = [NSMutableData dataWithHex:self];
    NSString *s = [[self class] base58WithData:d];

    OPENSSL_cleanse(d.mutableBytes, d.length);
    return s;
}

- (NSString *)base58ToHex
{
    return [NSString hexWithData:[self base58ToData]];
}

- (NSData *)base58checkToData
{
    NSData *d = [self base58ToData];
    
    if (d.length < 4) return nil;

    NSData *data = CFBridgingRelease(CFDataCreate(SecureAllocator(), d.bytes, d.length - 4));
    NSData *check = [NSData dataWithBytesNoCopy:(unsigned char *)d.bytes + d.length - 4 length:4 freeWhenDone:NO];
    NSData *hash = [data SHA256_2];
    
    if (! [[hash subdataWithRange:NSMakeRange(0, 4)] isEqualToData:check]) return nil;
    
    return data;
}

- (NSString *)hexToBase58check
{
    NSMutableData *d = [NSMutableData dataWithHex:self];
    NSString *s = [NSString base58checkWithData:d];
    
    OPENSSL_cleanse(d.mutableBytes, d.length);
    return s;
}

- (NSString *)base58checkToHex
{
    return [NSString hexWithData:[self base58checkToData]];
}

- (BOOL)isValidBitcoinAddress
{
    NSData *d = [self base58checkToData];
    
    if (d.length == 21) {
        switch (*(uint8_t *)d.bytes) {
            case BITCOIN_PUBKEY_ADDRESS:
            case BITCOIN_SCRIPT_ADDRESS:
                return ! BITCOIN_TESTNET;
                
            case BITCOIN_PUBKEY_ADDRESS_TEST:
            case BITCOIN_SCRIPT_ADDRESS_TEST:
                return BITCOIN_TESTNET;
        }
    }
        
    return NO;
}

@end

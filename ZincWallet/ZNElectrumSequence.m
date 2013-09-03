//
//  ZNElectrumSequence.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/27/13.
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

#import "ZNElectrumSequence.h"
#import "ZNKey.h"
#import "NSData+Hash.h"
#import "NSString+Base58.h"
#import <CommonCrypto/CommonDigest.h>
#import <openssl/ecdsa.h>
#import <openssl/obj_mac.h>

@implementation ZNElectrumSequence

- (NSData *)stretchKey:(NSData *)seed
{
    if (! seed) return nil;
    
    // Electrum uses a hex representation of the seed instead of the seed itself
    NSString *s = [NSString hexWithData:seed];
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), 0));
    
    d.length = s.length*2;
    [s getBytes:d.mutableBytes maxLength:s.length usedLength:NULL encoding:NSUTF8StringEncoding options:0
     range:NSMakeRange(0, s.length) remainingRange:NULL];
    [s getBytes:(unsigned char *)d.mutableBytes + s.length maxLength:s.length usedLength:NULL
     encoding:NSUTF8StringEncoding options:0 range:NSMakeRange(0, s.length) remainingRange:NULL];
    
    if (d.length < CC_SHA256_DIGEST_LENGTH) d.length = CC_SHA256_DIGEST_LENGTH;
    
    CC_SHA256(d.bytes, d.length, d.mutableBytes);
    
    d.length = CC_SHA256_DIGEST_LENGTH + s.length;
    [s getBytes:(unsigned char *)d.mutableBytes + CC_SHA256_DIGEST_LENGTH maxLength:s.length usedLength:NULL
     encoding:NSUTF8StringEncoding options:0 range:NSMakeRange(0, s.length) remainingRange:NULL];
    
    unsigned char *md = d.mutableBytes;
    CC_LONG l = d.length;
    
    for (NSUInteger i = 1; i < 100000; i++) {
        CC_SHA256(md, l, md);
    }
    
    d.length = CC_SHA256_DIGEST_LENGTH;
    return d;
}

- (NSData *)sequence:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
{
    if (! masterPublicKey) return nil;
    
    NSString *s = [NSString stringWithFormat:@"%u:%d:", n, internal ? 1 : 0];
    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), s.length + masterPublicKey.length));
    
    [d appendBytes:s.UTF8String length:[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    [d appendData:masterPublicKey];
    
    return [d SHA256_2];
}

#pragma mark - ZNKeySequence

- (NSData *)masterPublicKeyFromSeed:(NSData *)seed
{
    if (! seed) return nil;

    NSData *pubKey = [[ZNKey keyWithSecret:[self stretchKey:seed] compressed:NO] publicKey];
    
    if (pubKey.length < 1) return nil;
    
    // uncompressed pubkeys are prepended with 0x04... some sort of openssl key encapsulation
    return CFBridgingRelease(CFDataCreate(SecureAllocator(), (const uint8_t *)pubKey.bytes + 1, pubKey.length - 1));
}

- (NSData *)publicKey:(NSUInteger)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
{
    if (! masterPublicKey) return nil;

    NSMutableData *d = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), 0));
    NSData *z = [self sequence:n internal:internal masterPublicKey:masterPublicKey];
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM zbn;
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    EC_POINT *masterPubKeyPoint = EC_POINT_new(group), *pubKeyPoint = EC_POINT_new(group),
             *zPoint = EC_POINT_new(group);
    uint8_t form = EC_GROUP_get_point_conversion_form(group);

    [d appendBytes:&form length:1];
    [d appendData:masterPublicKey];

    BN_init(&zbn);
    BN_bin2bn(z.bytes, z.length, &zbn);
    EC_POINT_oct2point(group, masterPubKeyPoint, d.bytes, d.length, ctx);
    EC_POINT_mul(group, zPoint, &zbn, NULL, NULL, ctx);
    EC_POINT_add(group, pubKeyPoint, masterPubKeyPoint, zPoint, ctx);
    d.length = EC_POINT_point2oct(group, pubKeyPoint, form, d.mutableBytes, d.length, ctx);

    EC_POINT_clear_free(zPoint);
    EC_POINT_clear_free(pubKeyPoint);
    EC_POINT_clear_free(masterPubKeyPoint);
    EC_GROUP_free(group);
    BN_clear_free(&zbn);
    BN_CTX_free(ctx);
    return d;
}

- (NSString *)privateKey:(NSUInteger)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    return seed ? [[self privateKeys:@[@(n)] internal:internal fromSeed:seed] lastObject] : nil;
}

- (NSArray *)privateKeys:(NSArray *)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    if (! seed || ! n) return nil;
    if (n.count == 0) return @[];

    NSMutableArray *a = [NSMutableArray arrayWithCapacity:n.count];
    NSData *secexp = [self stretchKey:seed];
    NSData *_mpk = [[ZNKey keyWithSecret:secexp compressed:NO] publicKey];
    NSData *mpk = [NSData dataWithBytesNoCopy:(unsigned char *)_mpk.bytes + 1 length:_mpk.length - 1 freeWhenDone:NO];
    BN_CTX *ctx = BN_CTX_new();
    __block BIGNUM sequencebn, secexpbn, order;
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);

    BN_init(&sequencebn);
    BN_init(&secexpbn);
    BN_init(&order);
    EC_GROUP_get_order(group, &order, ctx);
    
    [n enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSData *sequence = [self sequence:[obj unsignedIntegerValue] internal:internal masterPublicKey:mpk];
        NSMutableData *pk = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), 33));

        BN_bin2bn(sequence.bytes, sequence.length, &sequencebn);
        BN_bin2bn(secexp.bytes, secexp.length, &secexpbn);
        
        BN_mod_add(&secexpbn, &secexpbn, &sequencebn, &order, ctx);

        pk.length = 33;
        *(unsigned char *)pk.mutableBytes = 0x80;
        BN_bn2bin(&secexpbn, (unsigned char *)pk.mutableBytes + pk.length - BN_num_bytes(&secexpbn));
        
        [a addObject:[NSString base58checkWithData:pk]];
    }];
    
    EC_GROUP_free(group);
    BN_free(&order);
    BN_clear_free(&secexpbn);
    BN_clear_free(&sequencebn);
    BN_CTX_free(ctx);
    return a;
}

@end

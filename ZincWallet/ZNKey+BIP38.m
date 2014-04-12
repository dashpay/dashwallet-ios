//
//  ZNKey+BIP38.m
//  ZincWallet
//
//  Created by Aaron Voisine on 4/9/14.
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

#import "ZNKey+BIP38.h"
#import "NSString+Base58.h"
#import "NSData+Hash.h"
#import "NSMutableData+Bitcoin.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonCryptor.h>
#import <openssl/crypto.h>
#import <openssl/ecdsa.h>
#import <openssl/obj_mac.h>

#define BIP38_COMPRESSED_FLAG 0x20
#define BIP38_SCRYPT_N        16384
#define BIP38_SCRYPT_R        8
#define BIP38_SCRYPT_P        8
#define BIP38_SCRYPT_EC_N     1024
#define BIP38_SCRYPT_EC_R     1
#define BIP38_SCRYPT_EC_P     1

#define BIP38_NOLS_MAGIC      "\x2C\xE9\xB3\xE1\xFF\x39\xE2\x53"
#define BIP38_LS_MAGIC        "\x2C\xE9\xB3\xE1\xFF\x39\xE2\x51"

#define rotl(a, b) (((a) << (b)) | ((a) >> (32 - (b))))

// salsa20/8 stream cypher: http://cr.yp.to/snuffle.html
static void salsa20_8(uint32_t b[16])
{
    uint32_t x00 = b[0], x01 = b[1], x02 = b[2],  x03 = b[3],  x04 = b[4],  x05 = b[5],  x06 = b[6],  x07 = b[7],
             x08 = b[8], x09 = b[9], x10 = b[10], x11 = b[11], x12 = b[12], x13 = b[13], x14 = b[14], x15 = b[15];

    for (int i = 0; i < 8; i += 2) {
        // operate on columns
        x04 ^= rotl(x00 + x12, 7), x08 ^= rotl(x04 + x00, 9), x12 ^= rotl(x08 + x04, 13), x00 ^= rotl(x12 + x08, 18);
        x09 ^= rotl(x05 + x01, 7), x13 ^= rotl(x09 + x05, 9), x01 ^= rotl(x13 + x09, 13), x05 ^= rotl(x01 + x13, 18);
        x14 ^= rotl(x10 + x06, 7), x02 ^= rotl(x14 + x10, 9), x06 ^= rotl(x02 + x14, 13), x10 ^= rotl(x06 + x02, 18);
        x03 ^= rotl(x15 + x11, 7), x07 ^= rotl(x03 + x15, 9), x11 ^= rotl(x07 + x03, 13), x15 ^= rotl(x11 + x07, 18);

        // operate on rows
        x01 ^= rotl(x00 + x03, 7), x02 ^= rotl(x01 + x00, 9), x03 ^= rotl(x02 + x01, 13), x00 ^= rotl(x03 + x02, 18);
        x06 ^= rotl(x05 + x04, 7), x07 ^= rotl(x06 + x05, 9), x04 ^= rotl(x07 + x06, 13), x05 ^= rotl(x04 + x07, 18);
        x11 ^= rotl(x10 + x09, 7), x08 ^= rotl(x11 + x10, 9), x09 ^= rotl(x08 + x11, 13), x10 ^= rotl(x09 + x08, 18);
        x12 ^= rotl(x15 + x14, 7), x13 ^= rotl(x12 + x15, 9), x14 ^= rotl(x13 + x12, 13), x15 ^= rotl(x14 + x13, 18);
    }

    b[0] += x00, b[1] += x01, b[2] += x02,  b[3] += x03,  b[4] += x04,  b[5] += x05,  b[6] += x06,  b[7] += x07;
    b[8] += x08, b[9] += x09, b[10] += x10, b[11] += x11, b[12] += x12, b[13] += x13, b[14] += x14, b[15] += x15;
}

static void blockmix_salsa8(uint64_t *dest, uint64_t *src, uint64_t *b, uint32_t r)
{
    memcpy(b, &src[(2*r - 1)*8], 64);

    for (uint32_t i = 0; i < 2*r; i += 2) {
        for (uint32_t j = 0; j < 8; j++) b[j] ^= src[i*8 + j];
        salsa20_8((uint32_t *)b);
        memcpy(&dest[i*4], b, 64);
        for (uint32_t j = 0; j < 8; j++) b[j] ^= src[i*8 + 8 + j];
        salsa20_8((uint32_t *)b);
        memcpy(&dest[i*4 + r*8], b, 64);
    }
}

static NSData *scrypt(NSData *password, NSData *salt, int64_t n, uint32_t r, uint32_t p, NSUInteger len)
{
    NSMutableData *d = [NSMutableData secureDataWithLength:len];
    uint8_t b[128*r*p];
    uint64_t x[16*r], y[16*r], z[8], *v = malloc(128*r*n);

    CCKeyDerivationPBKDF(kCCPBKDF2, password.bytes, password.length, salt.bytes, salt.length, kCCPRFHmacAlgSHA256, 1,
                         b, sizeof(b));

    for (uint32_t i = 0; i < p; i++) {
        for (uint32_t j = 0; j < 32*r; j++) {
            ((uint32_t *)x)[j] = CFSwapInt32LittleToHost(*(uint32_t *)&b[i*128*r + j*4]);
        }

        for (uint64_t j = 0; j < n; j += 2) {
            memcpy(&v[j*(16*r)], x, 128*r);
            blockmix_salsa8(y, x, z, r);
            memcpy(&v[(j + 1)*(16*r)], y, 128*r);
            blockmix_salsa8(x, y, z, r);
        }

        for (uint64_t j = 0, m; j < n; j += 2) {
            m = CFSwapInt64LittleToHost(x[(2*r - 1)*8]) & (n - 1);
            for (uint32_t k = 0; k < 16*r; k++) x[k] ^= v[m*(16*r) + k];
            blockmix_salsa8(y, x, z, r);
            m = CFSwapInt64LittleToHost(y[(2*r - 1)*8]) & (n - 1);
            for (uint32_t k = 0; k < 16*r; k++) y[k] ^= v[m*(16*r) + k];
            blockmix_salsa8(x, y, z, r);
        }

        for (uint32_t j = 0; j < 32*r; j++) {
            *(uint32_t *)&b[i*128*r + j*4] = CFSwapInt32HostToLittle(((uint32_t *)x)[j]);
        }
    }

    CCKeyDerivationPBKDF(kCCPBKDF2, password.bytes, password.length, b, sizeof(b), kCCPRFHmacAlgSHA256, 1,
                         d.mutableBytes, d.length);
    free(v);
    return d;
}

@implementation ZNKey (BIP38)

+ (instancetype)keyWithBIP38Key:(NSString *)key andPassphrase:(NSString *)passphrase
{
    return [[self alloc] initWithBIP38Key:key andPassphrase:passphrase];
}

- (instancetype)initWithBIP38Key:(NSString *)key andPassphrase:(NSString *)passphrase
{
    NSData *d = key.base58checkToData;

    if (d.length != 39) return nil;

    uint16_t prefix = CFSwapInt16BigToHost(*(uint16_t *)d.bytes);
    uint8_t flag = *((uint8_t *)d.bytes + 2);
    NSData *addresshash = [NSData dataWithBytesNoCopy:(uint8_t *)d.bytes + 3 length:4 freeWhenDone:NO];
    NSMutableData *secret = [NSMutableData secureDataWithLength:32];
    NSData *password = CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(),
                                                                              (__bridge CFStringRef)passphrase,
                                                                              kCFStringEncodingUTF8, 0));

    if (prefix == BIP38_NOEC_PREFIX) { // non EC multiplied key
        uint8_t *encrypted1 = (uint8_t *)d.bytes + 7, *encrypted2 = (uint8_t *)d.bytes + 23;
        NSData *derived = scrypt(password, addresshash, BIP38_SCRYPT_N, BIP38_SCRYPT_R, BIP38_SCRYPT_P, 64);
        uint8_t *derived1 = (uint8_t *)derived.bytes, *derived2 = (uint8_t *)derived.bytes + 32;
        size_t l;

        CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionECBMode, derived2, 32, NULL, encrypted1, 16,
                secret.mutableBytes, 16, &l);
        CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionECBMode, derived2, 32, NULL, encrypted2, 16,
                (uint8_t *)secret.mutableBytes + 16, 16, &l);

        for (size_t i = 0; i < secret.length/sizeof(uint64_t); i++) {
            ((uint64_t *)secret.mutableBytes)[i] ^= ((uint64_t *)derived1)[i];
        }
    }
    else if (prefix == BIP38_EC_PREFIX) { // EC multipled key
        uint8_t *entropy = (uint8_t *)d.bytes + 7;
        NSMutableData *encrypted1 = [NSMutableData dataWithBytes:(uint8_t *)d.bytes + 15 length:8]; // encrypted1[0...7]
        uint8_t *encrypted2 = (uint8_t *)d.bytes + 23;
        NSData *salt = [NSData dataWithBytesNoCopy:entropy length:(flag & BIP38_LS_FLAG) ? 4 : 8 freeWhenDone:NO];
        NSData *prefactor = scrypt(password, salt, BIP38_SCRYPT_N, BIP38_SCRYPT_R, BIP38_SCRYPT_P, 32), *pf;
        NSMutableData *passpoint = [NSMutableData secureDataWithLength:33], *x;
        BN_CTX *ctx = BN_CTX_new();
        BIGNUM passfactor, factorb, priv, order;
        EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
        EC_POINT *p = EC_POINT_new(group);

        if (flag & BIP38_LS_FLAG) {
            x = [NSMutableData secureDataWithData:prefactor];
            [x appendBytes:entropy length:8];
            pf = x.SHA256_2;
        }
        else pf = prefactor;

        BN_CTX_start(ctx);
        BN_init(&passfactor);
        BN_bin2bn(pf.bytes, (int)pf.length, &passfactor);
        EC_POINT_mul(group, p, &passfactor, NULL, NULL, ctx);
        EC_POINT_point2oct(group, p, POINT_CONVERSION_COMPRESSED, passpoint.mutableBytes, passpoint.length, ctx);
        EC_POINT_clear_free(p);

        x = [NSMutableData secureDataWithData:addresshash];
        [x appendBytes:entropy length:8];

        NSData *derived = scrypt(passpoint, x, BIP38_SCRYPT_EC_N, BIP38_SCRYPT_EC_R, BIP38_SCRYPT_EC_P, 64);
        uint8_t *derived1 = (uint8_t *)derived.bytes, *derived2 = (uint8_t *)derived.bytes + 32;
        NSMutableData *seedb = [NSMutableData secureDataWithLength:24], *o = [NSMutableData secureDataWithLength:16];
        size_t l;

        CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionECBMode, derived2, 32, NULL, encrypted2, 16,
                o.mutableBytes, o.length, &l); // o = (encrypted1[8...15] + seedb[16...23]) xor derived1[16...31]
        encrypted1.length = 16;
        ((uint64_t *)encrypted1.mutableBytes)[1] = ((uint64_t *)o.bytes)[0] ^ ((uint64_t *)derived1)[2];
        ((uint64_t *)seedb.mutableBytes)[2] = ((uint64_t *)o.bytes)[1] ^ ((uint64_t *)derived1)[3];

        CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionECBMode, derived2, 32, NULL, encrypted1.bytes, encrypted1.length,
                o.mutableBytes, o.length, &l); // o = seedb[0...15] xor derived1[0...15]
        ((uint64_t *)seedb.mutableBytes)[0] = ((uint64_t *)o.bytes)[0] ^ ((uint64_t *)derived1)[0];
        ((uint64_t *)seedb.mutableBytes)[1] = ((uint64_t *)o.bytes)[1] ^ ((uint64_t *)derived1)[1];

        BN_init(&factorb);
        BN_init(&priv);
        BN_init(&order);
        EC_GROUP_get_order(group, &order, ctx);
        BN_bin2bn(seedb.SHA256_2.bytes, CC_SHA256_DIGEST_LENGTH, &factorb);
        BN_mod_mul(&priv, &passfactor, &factorb, &order, ctx);
        BN_bn2bin(&priv, secret.mutableBytes + secret.length - BN_num_bytes(&priv));

        EC_GROUP_free(group);
        BN_free(&order);
        BN_clear_free(&priv);
        BN_clear_free(&factorb);
        BN_clear_free(&passfactor);
        BN_CTX_end(ctx);
        BN_CTX_free(ctx);
    }

    if (! (self = [self initWithSecret:secret compressed:flag & BIP38_COMPRESSED_FLAG])) return nil;

    if (*(int *)[self.address dataUsingEncoding:NSUTF8StringEncoding].SHA256_2.bytes != *(int *)addresshash.bytes) {
        NSLog(@"BIP38 bad passphrase");
        return nil;
    }

    return self;
}

@end

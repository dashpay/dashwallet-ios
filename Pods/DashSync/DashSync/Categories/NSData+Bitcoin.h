//
//  NSData+Bitcoin.h
//  DashSync
//
//  Created by Aaron Voisine on 10/09/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  Updated by Quantum Explorer on 05/11/18.
//  Copyright (c) 2018 Quantum Explorer <quantum@dash.org>
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

#import <Foundation/Foundation.h>
#import "IntTypes.h"

#define SEC_ATTR_SERVICE    @"org.dashfoundation.dash"

#define useDarkCoinSeed 0 //the darkcoin seed was retired quite a while ago

#if useDarkCoinSeed

#define BIP32_SEED_KEY "Darkcoin seed"

#define BIP32_XPRV_MAINNET     "\x02\xFE\x52\xCC" //// Dash BIP32 prvkeys start with 'drkp'
#define BIP32_XPUB_MAINNET     "\x02\xFE\x52\xF8" //// Dash BIP32 pubkeys start with 'drkv'
#define BIP32_XPRV_TESTNET     "\x02\xFE\x52\xCC"
#define BIP32_XPUB_TESTNET     "\x02\xFE\x52\xF8"

#else

#define BIP32_SEED_KEY "Bitcoin seed"

#define BIP32_XPRV_TESTNET     "\x04\x35\x83\x94"
#define BIP32_XPUB_TESTNET     "\x04\x35\x87\xCF"

#define BIP32_XPRV_MAINNET     "\x04\x88\xAD\xE4"
#define BIP32_XPUB_MAINNET     "\x04\x88\xB2\x1E"


#endif

#define RMD160_DIGEST_LENGTH (160/8)
#define MD5_DIGEST_LENGTH    (128/8)

#define VAR_INT16_HEADER 0xfd
#define VAR_INT32_HEADER 0xfe
#define VAR_INT64_HEADER 0xff

// bitcoin script opcodes: https://en.bitcoin.it/wiki/Script#Constants
#define OP_PUSHDATA1   0x4c
#define OP_PUSHDATA2   0x4d
#define OP_PUSHDATA4   0x4e
#define OP_DUP         0x76
#define OP_EQUAL       0x87
#define OP_EQUALVERIFY 0x88
#define OP_HASH160     0xa9
#define OP_CHECKSIG    0xac
#define OP_RETURN      0x6a

#define OP_SHAPESHIFT  0xb1 //not a bitcoin op code, used to identify shapeshift when placed after OP_RETURN
#define OP_SHAPESHIFT_SCRIPT 0xb3

//Keychain

BOOL setKeychainData(NSData *data, NSString *key, BOOL authenticated);
BOOL hasKeychainData(NSString *key, NSError **error);
NSData *getKeychainData(NSString *key, NSError **error);
BOOL setKeychainInt(int64_t i, NSString *key, BOOL authenticated);
int64_t getKeychainInt(NSString *key, NSError **error);
BOOL setKeychainString(NSString *s, NSString *key, BOOL authenticated);
NSString *getKeychainString(NSString *key, NSError **error);
BOOL setKeychainDict(NSDictionary *dict, NSString *key, BOOL authenticated);
NSDictionary *getKeychainDict(NSString *key, NSError **error);
BOOL setKeychainArray(NSArray *array, NSString *key, BOOL authenticated);
NSArray *getKeychainArray(NSString *key, NSError **error);

//Compact Size

UInt256 setCompact(int32_t nCompact);
uint8_t compactBits(UInt256 number);
int32_t getCompact(UInt256 number);
UInt256 uInt256Add(UInt256 a, UInt256 b);
UInt256 uInt256AddOne(UInt256 a);
UInt256 uInt256Neg(UInt256 a);
UInt256 uInt256Subtract(UInt256 a, UInt256 b);
UInt256 uInt256ShiftLeft(UInt256 a, uint8_t bits);
UInt256 uInt256ShiftRight(UInt256 a, uint8_t bits);
UInt256 uInt256Divide (UInt256 a,UInt256 b);
UInt256 uInt256MultiplyUInt32 (UInt256 a,uint32_t b);

//Serialization

// helper function for serializing BIP32 master public/private keys to standard export format
NSString *serialize(uint8_t depth, uint32_t fingerprint, uint32_t child, UInt256 chain, NSData *key,BOOL mainnet);
// helper function for deserializing BIP32 master public/private keys to standard export format
BOOL deserialize(NSString * string, uint8_t * depth, uint32_t * fingerprint, uint32_t * child, UInt256 * chain, NSData **key,BOOL mainnet);

//Hashing

void SHA1(void *_Nonnull md, const void *_Nonnull data, size_t len);
void SHA256(void *_Nonnull md, const void *_Nonnull data, size_t len);
void SHA512(void *_Nonnull md, const void *_Nonnull data, size_t len);
void RMD160(void *_Nonnull md, const void *_Nonnull data, size_t len);
void MD5(void *_Nonnull md, const void *_Nonnull data, size_t len);
void HMAC(void *_Nonnull md, void (*_Nonnull hash)(void *_Nonnull , const void *_Nonnull , size_t), size_t hlen,
          const void *_Nonnull key, size_t klen, const void *_Nonnull data, size_t dlen);
void PBKDF2(void *_Nonnull dk, size_t dklen, void (*_Nonnull hash)(void *_Nonnull , const void *_Nonnull , size_t),
            size_t hlen, const void *_Nonnull pw, size_t pwlen, const void *_Nonnull salt, size_t slen,
            unsigned rounds);

// poly1305 authenticator: https://tools.ietf.org/html/rfc7539
// must use constant time mem comparison when verifying mac to defend against timing attacks
void poly1305(void *_Nonnull mac16, const void *_Nonnull key32, const void *_Nonnull data, size_t len);

// chacha20 stream cypher: https://cr.yp.to/chacha.html
void chacha20(void *_Nonnull out, const void *_Nonnull key32, const void *_Nonnull iv8, const void *_Nonnull data,
              size_t len, uint64_t counter);

// chacha20-poly1305 authenticated encryption with associated data (AEAD): https://tools.ietf.org/html/rfc7539
size_t chacha20Poly1305AEADEncrypt(void *_Nullable out, size_t outLen, const void *_Nonnull key32,
                                   const void *_Nonnull nonce12, const void *_Nonnull data, size_t dataLen,
                                   const void *_Nonnull ad, size_t adLen);

size_t chacha20Poly1305AEADDecrypt(void *_Nullable out, size_t outLen, const void *_Nonnull key32,
                                   const void *_Nonnull nonce12, const void *_Nonnull data, size_t dataLen,
                                   const void *_Nonnull ad, size_t adLen);

@interface NSData (Bitcoin)

+ (nonnull instancetype)dataWithUInt256:(UInt256)n;
+ (nonnull instancetype)dataWithUInt160:(UInt160)n;
+ (nonnull instancetype)dataWithUInt128:(UInt128)n;
+ (nonnull instancetype)dataWithBase58String:(NSString *_Nonnull)b58str;

- (UInt160)SHA1;
- (UInt256)SHA256;
- (UInt256)SHA256_2;
- (UInt512)SHA512;
- (UInt160)RMD160;
- (UInt160)hash160;
- (UInt128)MD5;
- (NSData * _Nonnull)reverse;

- (uint8_t)UInt8AtOffset:(NSUInteger)offset;
- (uint16_t)UInt16AtOffset:(NSUInteger)offset;
- (uint32_t)UInt32AtOffset:(NSUInteger)offset;
- (uint64_t)UInt64AtOffset:(NSUInteger)offset;
- (UInt128)UInt128AtOffset:(NSUInteger)offset;
- (UInt160)UInt160AtOffset:(NSUInteger)offset;
- (UInt256)UInt256AtOffset:(NSUInteger)offset;
- (uint64_t)varIntAtOffset:(NSUInteger)offset length:(NSNumber * _Nonnull * _Nullable)length;
- (UInt256)hashAtOffset:(NSUInteger)offset;
- (NSString *_Nullable)stringAtOffset:(NSUInteger)offset length:(NSNumber * _Nonnull * _Nullable)length;
- (NSData *_Nonnull)dataAtOffset:(NSUInteger)offset length:(NSNumber * _Nonnull * _Nullable)length;

- (NSArray *_Nonnull)scriptElements; // an array of NSNumber and NSData objects representing each script element
- (int)intValue; // returns the opcode used to store the receiver in a script (i.e. OP_PUSHDATA1)

- (NSString *_Nonnull)base58String;
- (NSString *_Nonnull)shortHexString;
- (NSString *_Nonnull)hexString;

@end


@interface NSValue (Utils)

+ (nonnull instancetype)valueWithUInt256:(UInt256)uint;

@end

//
//  NSMutableData+Bitcoin.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/20/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "NSMutableData+Bitcoin.h"
#import "NSString+Base58.h"

#define VAR_INT16_HEADER 0xfd
#define VAR_INT32_HEADER 0xfe
#define VAR_INT64_HEADER 0xff

#define OP_PUSHDATA1   0x4c
#define OP_PUSHDATA2   0x4d
#define OP_PUSHDATA4   0x4e
#define OP_DUP         0x76
#define OP_EQUALVERIFY 0x88
#define OP_HASH160     0xa9
#define OP_CHECKSIG    0xac

@implementation NSMutableData (Bitcoin)

+ (size_t)sizeOfVarInt:(uint64_t)i
{
    if (i < VAR_INT16_HEADER) return sizeof(uint8_t);
    else if (i <= UINT16_MAX) return sizeof(uint8_t) + sizeof(uint16_t);
    else if (i <= UINT32_MAX) return sizeof(uint8_t) + sizeof(uint32_t);
    else return sizeof(uint8_t) + sizeof(uint64_t);
}

- (void)appendUInt8:(uint8_t)i
{
    [self appendBytes:&i length:sizeof(i)];
}

- (void)appendUInt16:(uint16_t)i
{
    uint16_t le = CFSwapInt16HostToLittle(i);
    
    [self appendBytes:&le length:sizeof(le)];    
}

- (void)appendUInt32:(uint32_t)i
{
    uint32_t le = CFSwapInt32HostToLittle(i);
    
    [self appendBytes:&le length:sizeof(le)];
}

- (void)appendUInt64:(uint64_t)i
{
    uint64_t le = CFSwapInt64HostToLittle(i);
    
    [self appendBytes:&le length:sizeof(le)];
}

- (void)appendVarInt:(uint64_t)i
{
    if (i < VAR_INT16_HEADER) {
        uint8_t payload = (uint8_t)i;
        
        [self appendBytes:&payload length:sizeof(payload)];
    }
    else if (i <= UINT16_MAX) {
        uint8_t header = VAR_INT16_HEADER;
        uint16_t payload = CFSwapInt16HostToLittle((uint16_t)i);
        
        [self appendBytes:&header length:sizeof(header)];
        [self appendBytes:&payload length:sizeof(payload)];
    }
    else if (i <= UINT32_MAX) {
        uint8_t header = VAR_INT32_HEADER;
        uint32_t payload = CFSwapInt32HostToLittle((uint32_t)i);
        
        [self appendBytes:&header length:sizeof(header)];
        [self appendBytes:&payload length:sizeof(payload)];
    }
    else {
        uint8_t header = VAR_INT64_HEADER;
        uint64_t payload = CFSwapInt64HostToLittle(i);
        
        [self appendBytes:&header length:sizeof(header)];
        [self appendBytes:&payload length:sizeof(payload)];
    }
}

- (void)appendString:(NSString *)s
{
    NSUInteger l = [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    [self appendVarInt:l];
    [self appendBytes:s.UTF8String length:l];
}

- (void)appendScriptPushData:(NSData *)d
{
    if (! d.length) {
        return;
    }
    else if (d.length < OP_PUSHDATA1) {
        [self appendUInt8:d.length];
    }
    else if (d.length < UINT8_MAX) {
        [self appendUInt8:OP_PUSHDATA1];
        [self appendUInt8:d.length];
    }
    else if (d.length < UINT16_MAX) {
        [self appendUInt8:OP_PUSHDATA2];
        [self appendUInt16:d.length];
    }
    else {
        [self appendUInt8:OP_PUSHDATA4];
        [self appendUInt32:d.length];
    }

    [self appendData:d];
}

- (void)appendScriptPubKeyForHash:(NSData *)hash
{
    [self appendUInt8:OP_DUP];
    [self appendUInt8:OP_HASH160];
    [self appendScriptPushData:hash]; // script is big endian
    [self appendUInt8:OP_EQUALVERIFY];
    [self appendUInt8:OP_CHECKSIG];
}

- (BOOL)appendScriptPubKeyForAddress:(NSString *)address
{
    NSData *d = [address base58checkToData];

    if (! d) return NO;

    [self appendScriptPubKeyForHash:[d subdataWithRange:NSMakeRange(1, d.length - 1)]];
    
    return YES;
}

@end

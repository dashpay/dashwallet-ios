//
//  NSMutableData+Dash.m
//  DashSync
//
//  Created by Aaron Voisine on 5/20/13.
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

#import "NSMutableData+Dash.h"
#import "NSData+Dash.h"
#import "NSString+Dash.h"
#import "DSChain.h"

static void *secureAllocate(CFIndex allocSize, CFOptionFlags hint, void *info)
{
    void *ptr = malloc(sizeof(CFIndex) + allocSize);
    
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
        memset(ptr, 0, size);
        free((CFIndex *)ptr - 1);
    }
}

static void *secureReallocate(void *ptr, CFIndex newsize, CFOptionFlags hint, void *info)
{
    // There's no way to tell ahead of time if the original memory will be deallocted even if the new size is smaller
    // than the old size, so just cleanse and deallocate every time.
    void *newptr = secureAllocate(newsize, hint, info);
    CFIndex size = *((CFIndex *)ptr - 1);
    
    if (newptr && size) {
        memcpy(newptr, ptr, (size < newsize) ? size : newsize);
        secureDeallocate(ptr, info);
    }
    
    return newptr;
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

@implementation NSMutableData (Dash)

+ (NSMutableData *)secureData
{
    return [self secureDataWithCapacity:0];
}

+ (NSMutableData *)secureDataWithCapacity:(NSUInteger)aNumItems
{
    return CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), aNumItems));
}

+ (NSMutableData *)secureDataWithLength:(NSUInteger)length
{
    NSMutableData *d = [self secureDataWithCapacity:length];

    d.length = length;
    return d;
}

+ (NSMutableData *)secureDataWithData:(NSData *)data
{
    return CFBridgingRelease(CFDataCreateMutableCopy(SecureAllocator(), 0, (CFDataRef)data));
}

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
    i = CFSwapInt16HostToLittle(i);
    [self appendBytes:&i length:sizeof(i)];
}

- (void)appendUInt32:(uint32_t)i
{
    i = CFSwapInt32HostToLittle(i);
    [self appendBytes:&i length:sizeof(i)];
}

- (void)appendUInt64:(uint64_t)i
{
    i = CFSwapInt64HostToLittle(i);
    [self appendBytes:&i length:sizeof(i)];
}

- (void)appendUInt128:(UInt128)i
{
    [self appendBytes:&i length:sizeof(i)];
}

- (void)appendUInt160:(UInt160)i
{
    [self appendBytes:&i length:sizeof(i)];
}

- (void)appendUInt256:(UInt256)i
{
    [self appendBytes:&i length:sizeof(i)];
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

- (void)appendCoinbaseMessage:(NSString *)message atHeight:(uint32_t)height
{
    NSUInteger l = [message lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    uint8_t bytesInHeight;
    if (height < VAR_INT16_HEADER) {
        uint8_t header = l;
        uint8_t payload = (uint8_t)height;
        [self appendBytes:&header length:sizeof(header)];
        [self appendBytes:&payload length:sizeof(payload)];
    }
    else if (height <= UINT16_MAX) {
        uint8_t header = VAR_INT16_HEADER + l;
        uint16_t payload = CFSwapInt16HostToLittle((uint16_t)height);
        
        [self appendBytes:&header length:sizeof(header)];
        [self appendBytes:&payload length:sizeof(payload)];
    }
    else if (height <= UINT32_MAX) {
        uint8_t header = VAR_INT32_HEADER + l;
        uint32_t payload = CFSwapInt32HostToLittle((uint32_t)height);
        
        [self appendBytes:&header length:sizeof(header)];
        [self appendBytes:&payload length:sizeof(payload)];
    }
    [self appendBytes:message.UTF8String length:l];
}

- (void)appendDevnetGenesisCoinbaseMessage:(NSString *)message
{
    //A little weirder
    uint8_t l = (uint8_t)[message lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    uint8_t a = 0x51;
    uint8_t fullLength = l + 2;
    [self appendBytes:&fullLength length:sizeof(fullLength)];
    [self appendBytes:&a length:sizeof(a)];
    [self appendBytes:&l length:sizeof(l)];
    [self appendBytes:message.UTF8String length:l];
}

- (void)appendString:(NSString *)s
{
    NSUInteger l = [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    [self appendVarInt:l];
    [self appendBytes:s.UTF8String length:l];
}

// MARK: - bitcoin script

- (void)appendScriptPushData:(NSData *)d
{
    if (d.length == 0) {
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
        [self appendUInt32:(uint32_t)d.length];
    }

    [self appendData:d];
}

- (void)appendScriptPubKeyForAddress:(NSString *)address forChain:(DSChain*)chain
{
    uint8_t pubkeyAddress, scriptAddress;
    NSData *d = address.base58checkToData;

    if (d.length != 21) return;

    uint8_t version = *(const uint8_t *)d.bytes;
    NSData *hash = [d subdataWithRange:NSMakeRange(1, d.length - 1)];

    if ([chain isMainnet]) {
        pubkeyAddress = DASH_PUBKEY_ADDRESS;
        scriptAddress = DASH_SCRIPT_ADDRESS;
    } else {
        pubkeyAddress = DASH_PUBKEY_ADDRESS_TEST;
        scriptAddress = DASH_SCRIPT_ADDRESS_TEST;
    }

    if (version == pubkeyAddress) {
        [self appendUInt8:OP_DUP];
        [self appendUInt8:OP_HASH160];
        [self appendScriptPushData:hash];
        [self appendUInt8:OP_EQUALVERIFY];
        [self appendUInt8:OP_CHECKSIG];
    }
    else if (version == scriptAddress) {
        [self appendUInt8:OP_HASH160];
        [self appendScriptPushData:hash];
        [self appendUInt8:OP_EQUAL];
    }
}

- (void)appendShapeshiftMemoForAddress:(NSString *)address
{
    static uint8_t pubkeyAddress = BITCOIN_PUBKEY_ADDRESS, scriptAddress = BITCOIN_SCRIPT_ADDRESS;
    NSData *d = address.base58checkToData;
    
    if (d.length != 21) return;
    
    uint8_t version = *(const uint8_t *)d.bytes;
    NSData *hash = [d subdataWithRange:NSMakeRange(1, d.length - 1)];
    NSMutableData * hashMutableData = [[NSMutableData alloc] init];
    if (version == scriptAddress) {
        [hashMutableData appendUInt8:OP_SHAPESHIFT_SCRIPT];
    } else {
        [hashMutableData appendUInt8:OP_SHAPESHIFT]; //shapeshift is actually part of the message
    }
    [hashMutableData appendData:hash];
    [self appendUInt8:OP_RETURN];
    [self appendScriptPushData:hashMutableData];
}


- (void)appendBitcoinScriptPubKeyForAddress:(NSString *)address forChain:(DSChain*)chain
{
    uint8_t pubkeyAddress, scriptAddress;
    NSData *d = address.base58checkToData;
    
    if (d.length != 21) return;
    
    uint8_t version = *(const uint8_t *)d.bytes;
    NSData *hash = [d subdataWithRange:NSMakeRange(1, d.length - 1)];
    
    
    if ([chain isMainnet]) {
        pubkeyAddress = BITCOIN_PUBKEY_ADDRESS;
        scriptAddress = BITCOIN_SCRIPT_ADDRESS;
    } else {
        pubkeyAddress = BITCOIN_PUBKEY_ADDRESS_TEST;
        scriptAddress = BITCOIN_SCRIPT_ADDRESS_TEST;
    }
    
    if (version == pubkeyAddress) {
        [self appendUInt8:OP_DUP];
        [self appendUInt8:OP_HASH160];
        [self appendScriptPushData:hash];
        [self appendUInt8:OP_EQUALVERIFY];
        [self appendUInt8:OP_CHECKSIG];
    }
    else if (version == scriptAddress) {
        [self appendUInt8:OP_HASH160];
        [self appendScriptPushData:hash];
        [self appendUInt8:OP_EQUAL];
    }
}
// MARK: - dash protocol

- (void)appendProposalInfo:(NSData*)proposalInfo {
    static uint8_t pubkeyAddress = BITCOIN_PUBKEY_ADDRESS, scriptAddress = BITCOIN_SCRIPT_ADDRESS;
    NSMutableData * hashMutableData = [[NSMutableData alloc] init];

    [hashMutableData appendUInt256:proposalInfo.SHA256_2];
    [self appendUInt8:OP_RETURN];
    [self appendScriptPushData:hashMutableData];
}

- (void)appendMessage:(NSData *)message type:(NSString *)type forChain:(DSChain*)chain
{
    [self appendUInt32:chain.magicNumber];
    [self appendNullPaddedString:type length:12];
    [self appendUInt32:(uint32_t)message.length];
    [self appendBytes:message.SHA256_2.u32 length:4];
    [self appendBytes:message.bytes length:message.length];
}

- (void)appendNullPaddedString:(NSString *)s length:(NSUInteger)length
{
    NSUInteger l = [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    [self appendBytes:s.UTF8String length:l];

    while (l++ < length) {
        [self appendBytes:"\0" length:1];
    }
}

- (void)appendNetAddress:(uint32_t)address port:(uint16_t)port services:(uint64_t)services
{
    address = CFSwapInt32HostToBig(address);
    port = CFSwapInt16HostToBig(port);
    
    [self appendUInt64:services];
    [self appendBytes:"\0\0\0\0\0\0\0\0\0\0\xFF\xFF" length:12]; // IPv4 mapped IPv6 header
    [self appendBytes:&address length:sizeof(address)];
    [self appendBytes:&port length:sizeof(port)];
}

@end

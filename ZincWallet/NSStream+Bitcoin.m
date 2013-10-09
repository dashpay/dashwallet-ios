//
//  NSStream+Bitcoin.m
//  ZincWallet
//
//  Created by Aaron Voisine on 10/8/13.
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

#import "NSStream+Bitcoin.h"
#import "NSString+Base58.h" // testnet #define
#import "NSData+Hash.h"

#if BITCOIN_TESTNET
#define MAGIC_NUMBER 0x0709110B
#else
#define MAGIC_NUMBER 0xD9B4BEF9
#endif

#define VAR_INT16_HEADER 0xfd
#define VAR_INT32_HEADER 0xfe
#define VAR_INT64_HEADER 0xff

@implementation NSStream (Bitcoin)

- (NSInteger)writeUInt8:(uint8_t)i
{
    return [(NSOutputStream *)self write:(uint8_t *)&i maxLength:sizeof(i)];
}

- (NSInteger)writeUInt16:(uint16_t)i
{
    i = CFSwapInt16HostToLittle(i);
    
    return [(NSOutputStream *)self write:(uint8_t *)&i maxLength:sizeof(i)];
}

- (NSInteger)writeUInt32:(uint32_t)i
{
    i = CFSwapInt32HostToLittle(i);
    
    return [(NSOutputStream *)self write:(uint8_t *)&i maxLength:sizeof(i)];
}

- (NSInteger)writeUInt64:(uint64_t)i
{
    i = CFSwapInt64HostToLittle(i);
    
    return [(NSOutputStream *)self write:(uint8_t *)&i maxLength:sizeof(i)];
}

- (NSInteger)writeVarInt:(uint64_t)i
{
    NSInteger r = 0, l = 0;

    if (i < VAR_INT16_HEADER) {
        uint8_t payload = (uint8_t)i;
        
        return [(NSOutputStream *)self write:&payload maxLength:sizeof(payload)];
    }
    else if (i <= UINT16_MAX) {
        uint8_t header = VAR_INT16_HEADER;
        uint16_t payload = CFSwapInt16HostToLittle((uint16_t)i);
        
        if ((r = [(NSOutputStream *)self write:&header maxLength:sizeof(header)]) < 0) return r;
        return (l = [(NSOutputStream *)self write:(uint8_t *)&payload maxLength:sizeof(payload)]) < 0 ? l : r + l;
    }
    else if (i <= UINT32_MAX) {
        uint8_t header = VAR_INT32_HEADER;
        uint32_t payload = CFSwapInt32HostToLittle((uint32_t)i);
        
        if ((r = [(NSOutputStream *)self write:&header maxLength:sizeof(header)]) < 0) return r;
        return (l = [(NSOutputStream *)self write:(uint8_t *)&payload maxLength:sizeof(payload)]) < 0 ? l : r + l;
    }
    else {
        uint8_t header = VAR_INT64_HEADER;
        uint64_t payload = CFSwapInt64HostToLittle(i);
        
        if ((r = [(NSOutputStream *)self write:&header maxLength:sizeof(header)]) < 0) return r;
        return (l = [(NSOutputStream *)self write:(uint8_t *)&payload maxLength:sizeof(payload)]) < 0 ? l : r + l;
    }
}

- (NSInteger)writeString:(NSString *)s nullPaddedToLength:(NSUInteger)length
{
    NSInteger r = 0, l = 0;
    
    if ((r = [(NSOutputStream *)self write:(const uint8_t *)s.UTF8String
              maxLength:[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]]) < 0) return r;

    while (length > r && l > 0) {
        if ((l = [(NSOutputStream *)self write:(const uint8_t *)"\0" maxLength:1]) < 0) return l;
        r += l;
    }
    
    return r;
}

- (NSInteger)writeData:(NSData *)d
{
    return [(NSOutputStream *)self write:d.bytes maxLength:d.length];
}

- (NSInteger)writeCommand:(NSString *)command payload:(NSData *)payload
{
    NSInteger r = 0, l = 0;
    
    if ((r = [self writeUInt32:MAGIC_NUMBER]) < 0) return r;
    if ((l = [self writeString:command nullPaddedToLength:12]) < 0) return l;
    r += l;
    if ((l = [self writeUInt32:(uint32_t)payload.length]) < 0) return l;
    r += l;
    if ((l = [self writeData:[[payload SHA256_2] subdataWithRange:NSMakeRange(0, 4)]]) < 0) return l;
    r += l;
    return (l = [self writeData:payload]) < 0 ? l : r + l;
}

@end

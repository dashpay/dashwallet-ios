//
//  ZNPeer.m
//  ZincWallet
//
//  Created by Aaron Voisine on 10/9/13.
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

#import "ZNPeer.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Hash.h"
#import <arpa/inet.h>

#define USERAGENT [NSString stringWithFormat:@"/zincwallet:%@/", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]]
#define MSG_HEADER_LENGTH      24
#define MAX_PAYLOAD_LENGTH     0x02000000
#define ENABLED_SERVICES       0 // we don't provide full blocks to remote nodes
#define PROTOCOL_VERSION       70001
#define MIN_PROTO_VERSION      209 // peers earlier than this protocol version not supported
#define LOCAL_HOST             0x010000ff
#define REFERENCE_BLOCK_HEIGHT 250000

#define CMD_VERSION     @"version"
#define CMD_VERACK      @"verack"
#define CMD_ADDR        @"addr"
#define CMD_INV         @"inv"
#define CMD_GETDATA     @"getdata"
#define CMD_NOTFOUND    @"notfound"
#define CMD_GETBLOCKS   @"getblocks"
#define CMD_GETHEADERS  @"getheaders"
#define CMD_TX          @"tx"
#define CMD_BLOCK       @"block"
#define CMD_HEADERS     @"headers"
#define CMD_GETADDR     @"getaddr"
#define CMD_MEMPOOL     @"mempool"
#define CMD_CHECKORDER  @"checkorder"
#define CMD_SUBMITORDER @"submitorder"
#define CMD_REPLY       @"reply"
#define CMD_PING        @"ping"
#define CMD_PONG        @"pong"
#define CMD_FILTERLOAD  @"filterload"
#define CMD_FILTERADD   @"filteradd"
#define CMD_FILTERCLEAR @"filterclear"
#define CMD_MERKLEBLOCK @"merkleblock"
#define CMD_ALERT       @"alert"

#define llurand() (((long long unsigned)mrand48() << (sizeof(unsigned)*8)) | (unsigned)mrand48())

@interface ZNPeer ()

@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableData *msgHeader, *msgPayload, *outputBuffer;

@end

@implementation ZNPeer

+ (instancetype)peerWithAddress:(uint32_t)address andPort:(uint16_t)port
{
    return [[self alloc] initWithAddress:address andPort:port];
}

- (instancetype)initWithAddress:(uint32_t)address andPort:(uint16_t)port
{
    if (! (self = [super init])) return nil;
    
    _address = address;
    _port = port;
    
    self.msgHeader = [NSMutableData data];
    self.msgPayload = [NSMutableData data];
    
    return self;
}

- (void)connect
{
    struct in_addr addr = { self.address };
    NSString *host = [NSString stringWithUTF8String:inet_ntoa(addr)];
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host, self.port, &readStream, &writeStream);
    
    NSInputStream *inStream = CFBridgingRelease(readStream);
    NSOutputStream *outStream = CFBridgingRelease(writeStream);
    
    inStream.delegate = outStream.delegate = self;
    
    // we may want to use a different thread for each peer
    [inStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    [inStream open];
    [outStream open];
    
    [self sendVersion];
}

- (void)sendCommand:(NSString *)command payload:(NSData *)payload
{
    [self.outputBuffer appendCommand:command payload:payload];

    NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];

    if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
}

- (void)sendVersion
{
    NSMutableData *d = [NSMutableData data];
    
    [d appendUInt32:PROTOCOL_VERSION]; // version
    [d appendUInt64:ENABLED_SERVICES]; // services
    [d appendUInt64:[NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970]; // timestamp
    [d appendNetAddress:self.address port:self.port services:self.services]; // address of remote peer
    //XXXX does using 127.0.0.1 work?
    [d appendNetAddress:LOCAL_HOST port:STANDARD_PORT services:ENABLED_SERVICES]; // address of local peer
    [d appendUInt64:llurand()]; // random nonce
    [d appendString:USERAGENT]; // user agent
    //TODO: XXXX get last block stored in core data
    [d appendUInt32:REFERENCE_BLOCK_HEIGHT]; // last block received
    [d appendUInt8:0]; // relay transactions (no for SPV bloom filter mode)
    
    [self sendCommand:@"version" payload:d];
}

- (void)acceptCommand:(NSString *)command payload:(NSData *)payload
{
    if ([CMD_VERSION isEqual:command]) {
        // send verack
    }
    else if ([CMD_VERACK isEqual:command]) {
        // peer accepted out version message
    }
}

#pragma mark - hash

#define FNV32_PRIME  0x01000193u
#define FNV32_OFFSET 0x811C9DC5u

// FNV32-1a hash of the ip address and port number: http://www.isthe.com/chongo/tech/comp/fnv/index.html#FNV-1a
- (NSUInteger)hash
{
    uint32_t hash = FNV32_OFFSET;
    
    hash = (hash^((self.address >> 24) & 0xFF))*FNV32_PRIME;
    hash = (hash^((self.address >> 16) & 0xFF))*FNV32_PRIME;
    hash = (hash^((self.address >> 8) & 0xFF))*FNV32_PRIME;
    hash = (hash^((self.address >> 0) & 0xFF))*FNV32_PRIME;
    hash = (hash^((self.port >> 8) & 0xFF))*FNV32_PRIME;
    hash = (hash^((self.port >> 0) & 0xFF))*FNV32_PRIME;
    
    return hash;
}

// two peers are equal if they share an ip address and port number
- (BOOL)isEqual:(id)object
{
    return [object isKindOfClass:[ZNPeer class]] &&
           self.address == [(ZNPeer *)object address] && self.port == [(ZNPeer *)object port];
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    const uint8_t *b = NULL;
    NSString *command = nil;
    uint32_t length = 0, checksum = 0;
    
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"Stream opened");
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (aStream != self.inputStream) break;

            while ([(NSInputStream *)aStream hasBytesAvailable]) {
                NSInteger hlen = self.msgHeader.length, plen = self.msgPayload.length, l = 0;

                if (hlen < MSG_HEADER_LENGTH) {
                    self.msgHeader.length = MSG_HEADER_LENGTH;
                    l = [(NSInputStream *)aStream read:self.msgHeader.mutableBytes maxLength:self.msgHeader.length];
                    self.msgHeader.length = l < 0 ? hlen : hlen + l;
                    
                    if (l < 0 || (self.msgHeader.length > sizeof(uint32_t) &&
                                  CFSwapInt32LittleToHost(*(uint32_t *)self.msgHeader.bytes) != MAGIC_NUMBER)) {
                        NSLog(@"error reading message from peer");
                        goto breakout;
                    }
                    else if (self.msgHeader.length < MSG_HEADER_LENGTH) continue;
                }
                
                b = self.msgHeader.bytes;
                command = [[NSString alloc] initWithBytes:&b[4] length:12 encoding:NSUTF8StringEncoding];
                length = CFSwapInt32LittleToHost(*(uint32_t *)&b[16]);
                checksum = *(uint32_t *)&b[20];
                
                if (length > MAX_PAYLOAD_LENGTH) {
                    NSLog(@"error reading message from peer, message too long");
                    goto breakout;
                }
                else if (plen < length) {
                    self.msgPayload.length = length;
                    l = [(NSInputStream *)aStream read:self.msgPayload.mutableBytes maxLength:self.msgPayload.length];
                    self.msgPayload.length = l < 0 ? plen : plen + l;
                
                    if (l < 0) {
                        NSLog(@"error reading message from peer");
                        goto breakout;
                    }
                    else if (self.msgPayload.length < length) continue;
                }

                if (*(uint32_t *)[self.msgPayload SHA256_2].bytes != checksum) {
                    NSLog(@"error reading message from peer, invalid checksum");
                    goto breakout;
                }
                else [self acceptCommand:command payload:self.msgPayload];
                
breakout:
                // reset and wait for next message
                self.msgHeader.length = 0;
                self.msgPayload.length = 0;
            }
            break;
           
        case NSStreamEventHasSpaceAvailable:
            if (aStream != self.outputStream) break;
            
            while (self.outputBuffer.length > 0 && [(NSOutputStream *)aStream hasSpaceAvailable]) {
                NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];

                if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
            }
            break;
        
        case NSStreamEventErrorOccurred:
            NSLog(@"Can not connect to the host!");
            [aStream close];
            [aStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            //XXX remove peer
            break;
            
        case NSStreamEventEndEncountered:
            [aStream close];
            [aStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            //XXX remove peer or reconnect or something
            break;
            
        default:
            NSLog(@"Unknown event");
    }
}

@end

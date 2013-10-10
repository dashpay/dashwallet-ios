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
#import "NSData+Bitcoin.h"
#import "NSData+Hash.h"
#import <arpa/inet.h>

#define USERAGENT [NSString stringWithFormat:@"/zincwallet:%@/", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]]

#define HEADER_LENGTH          24
#define MAX_MSG_LENGTH         0x02000000
#define ENABLED_SERVICES       0 // we don't provide full blocks to remote nodes
#define PROTOCOL_VERSION       70001
#define MIN_PROTO_VERSION      209 // peers earlier than this protocol version not supported
#define LOCAL_HOST             0x7f000001
#define REFERENCE_BLOCK_HEIGHT 250000

#define MSG_VERSION     @"version"
#define MSG_VERACK      @"verack"
#define MSG_ADDR        @"addr"
#define MSG_INV         @"inv"
#define MSG_GETDATA     @"getdata"
#define MSG_NOTFOUND    @"notfound"
#define MSG_GETBLOCKS   @"getblocks"
#define MSG_GETHEADERS  @"getheaders"
#define MSG_TX          @"tx"
#define MSG_BLOCK       @"block"
#define MSG_HEADERS     @"headers"
#define MSG_GETADDR     @"getaddr"
#define MSG_MEMPOOL     @"mempool"
#define MSG_CHECKORDER  @"checkorder"
#define MSG_SUBMITORDER @"submitorder"
#define MSG_REPLY       @"reply"
#define MSG_PING        @"ping"
#define MSG_PONG        @"pong"
#define MSG_FILTERLOAD  @"filterload"
#define MSG_FILTERADD   @"filteradd"
#define MSG_FILTERCLEAR @"filterclear"
#define MSG_MERKLEBLOCK @"merkleblock"
#define MSG_ALERT       @"alert"

#define llurand() (((long long unsigned)mrand48() << (sizeof(unsigned)*8)) | (unsigned)mrand48())

@interface ZNPeer ()

@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableData *msgHeader, *msgPayload, *outputBuffer;
@property (nonatomic, assign) BOOL sentVerack, gotVerack;

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
    self.outputBuffer = [NSMutableData data];
    
    return self;
}

- (void)connect
{
    struct in_addr addr = { self.address };
    char s[INET_ADDRSTRLEN];
    NSString *host = [NSString stringWithUTF8String:inet_ntop(AF_INET, &addr, s, INET_ADDRSTRLEN)];
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    
    NSLog(@"connecting to %@:%u", host, self.port);
    _status = connecting;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host, self.port, &readStream, &writeStream);
    self.inputStream = CFBridgingRelease(readStream);
    self.outputStream = CFBridgingRelease(writeStream);
    self.inputStream.delegate = self.outputStream.delegate = self;
    
    // we may want to use a different thread for each peer
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    [self.inputStream open];
    [self.outputStream open];
    
    [self sendVersionMessage];
}

- (void)disconnect
{
    [self.inputStream close];
    [self.outputStream close];

    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    self.gotVerack = self.sentVerack = NO;
    _status = disconnected;
    [self.delegate peerDisconnected:self];
}

// change state to connected if appropriate
- (void)setConnected
{
    if (self.status != connecting || ! self.sentVerack || ! self.gotVerack) return;

    _status = connected;
    [self.delegate peerConnected:self];
    
    //TODO: XXXX send bloom filters
}

#pragma mark - send

- (void)sendMessage:(NSData *)message type:(NSString *)type
{
    [self.outputBuffer appendMessage:message type:type];
    
    while (self.outputBuffer.length > 0 && [self.outputStream hasSpaceAvailable]) {
        NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];

        if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
    }
}

- (void)sendVersionMessage
{
    NSMutableData *msg = [NSMutableData data];
    
    NSLog(@"sending version");
    
    [msg appendUInt32:PROTOCOL_VERSION]; // version
    [msg appendUInt64:ENABLED_SERVICES]; // services
    [msg appendUInt64:[NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970]; // timestamp
    //XXXX we have endianess problems
    [msg appendNetAddress:self.address port:self.port services:self.services]; // address of remote peer
    //XXXX does using 127.0.0.1 work?
    [msg appendNetAddress:LOCAL_HOST port:STANDARD_PORT services:ENABLED_SERVICES]; // address of local peer
    [msg appendUInt64:llurand()]; // random nonce
    [msg appendString:USERAGENT]; // user agent
    //TODO: XXXX get last block stored in core data
    [msg appendUInt32:REFERENCE_BLOCK_HEIGHT]; // last block received
    [msg appendUInt8:0]; // relay transactions (no for SPV bloom filter mode)
    
    //TODO: need some sort of timeout for verack
    [self sendMessage:msg type:MSG_VERSION];
}

- (void)sendVerackMessage
{
    NSLog(@"sending verack");
    
    [self sendMessage:[NSData data] type:MSG_VERACK];
    self.sentVerack = YES;
    [self setConnected];
}

#pragma mark - accept

- (void)acceptMessage:(NSData *)message type:(NSString *)type
{
    if ([MSG_VERSION isEqual:type]) {
        [self acceptVersionMessage:message];
    }
    else if ([MSG_VERACK isEqual:type]) {
        [self acceptVerackMessage:message];
    }
    else NSLog(@"dropping %@, handler not implemented", type);
}

- (void)acceptVersionMessage:(NSData *)message
{
    NSUInteger l = 0;
    
    _version = [message UInt32AtOffset:0];
    
    if (self.version < MIN_PROTO_VERSION) {
        [self disconnect];
        return;
    }
    
    _services = [message UInt64AtOffset:4];
    _timestamp = [message UInt64AtOffset:12];
    _useragent = [message stringAtOffset:80 length:&l];
    _lastblock = [message UInt32AtOffset:80 + l];
    
    NSLog(@"got version");
    
    [self sendVerackMessage];
}

- (void)acceptVerackMessage:(NSData *)message
{
    if (message.length != 0) {
        NSLog(@"error reading message, malformed verack payload");
        return;
    }
    
    NSLog(@"got verack");
    self.gotVerack = YES;
    [self setConnected];
}

#pragma mark - hash

#define FNV32_PRIME  0x01000193u
#define FNV32_OFFSET 0x811C9DC5u

// FNV32-1a hash of the ip address and port number: http://www.isthe.com/chongo/tech/comp/fnv/index.html#FNV-1a
- (NSUInteger)hash
{
    uint32_t hash = FNV32_OFFSET;
    
    hash = (hash ^ ((self.address >> 24) & 0xFF))*FNV32_PRIME;
    hash = (hash ^ ((self.address >> 16) & 0xFF))*FNV32_PRIME;
    hash = (hash ^ ((self.address >> 8) & 0xFF))*FNV32_PRIME;
    hash = (hash ^ ((self.address >> 0) & 0xFF))*FNV32_PRIME;
    hash = (hash ^ ((self.port >> 8) & 0xFF))*FNV32_PRIME;
    hash = (hash ^ ((self.port >> 0) & 0xFF))*FNV32_PRIME;
    
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
    struct in_addr addr = { self.address };
    char s[INET_ADDRSTRLEN];

    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"%s:%d %@ stream connected", inet_ntop(AF_INET, &addr, s, INET_ADDRSTRLEN), self.port,
                  aStream == self.inputStream ? @"input" : aStream == self.outputStream ? @"output" : @"unkown");
            // no break; continue to next case and send any queued output
        case NSStreamEventHasSpaceAvailable:
            if (aStream != self.outputStream) break;
            
            while (self.outputBuffer.length > 0 && [self.outputStream hasSpaceAvailable]) {
                NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];
                
                if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
            }
            
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (aStream != self.inputStream) break;

            while ([self.inputStream hasBytesAvailable]) {
                NSString *type = nil;
                uint32_t length = 0, checksum = 0;
                NSInteger headerLen = self.msgHeader.length, payloadLen = self.msgPayload.length, l = 0;

                if (headerLen < HEADER_LENGTH) { // read message header
                    self.msgHeader.length = HEADER_LENGTH;
                    l = [self.inputStream read:(uint8_t *)self.msgHeader.mutableBytes + headerLen
                         maxLength:self.msgHeader.length];
                    
                    if (l < 0) {
                        NSLog(@"error reading message from peer");
                        goto reset;
                    }
                    
                    self.msgHeader.length = headerLen + l;
                    
                    // consume one byte at a time, until we find the magic number that starts a new message header
                    while (self.msgHeader.length >= sizeof(uint32_t) &&
                           [self.msgHeader UInt32AtOffset:0] != MAGIC_NUMBER) {
                        NSLog(@"%c", *(char *)self.msgHeader.bytes);
                        [self.msgHeader replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
                    }
                    
                    if (self.msgHeader.length < HEADER_LENGTH) continue; // wait for more stream input
                }
                
                if ([self.msgHeader UInt8AtOffset:15] != 0) { // verify that the msg type field is null terminated
                    NSLog(@"error reading message from peer, malformed message header");
                    goto reset;
                }
                
                type = [NSString stringWithUTF8String:(char *)self.msgHeader.bytes + 4];
                length = [self.msgHeader UInt32AtOffset:16];
                checksum = [self.msgHeader UInt32AtOffset:20];
                
                if (length > MAX_MSG_LENGTH) { // check message length
                    NSLog(@"error reading message from peer, message too long");
                    goto reset;
                }
                
                if (payloadLen < length) { // read message payload
                    self.msgPayload.length = length;
                    l = [self.inputStream read:(uint8_t *)self.msgPayload.mutableBytes + payloadLen
                         maxLength:self.msgPayload.length];
                
                    if (l < 0) {
                        NSLog(@"error reading message from peer");
                        goto reset;
                    }
                    
                    self.msgPayload.length = payloadLen + l;
                    if (self.msgPayload.length < length) continue; // wait for more stream input
                }

                if (*(uint32_t *)[self.msgPayload SHA256_2].bytes != checksum) { // verify checksum
                    NSLog(@"error reading message from peer, invalid checksum");
                    goto reset;
                }
                
                [self acceptMessage:self.msgPayload type:type]; // process message
                
reset:          // reset for next message
                self.msgHeader.length = self.msgPayload.length = 0;
            }
            
            break;
            
        case NSStreamEventErrorOccurred:
            NSLog(@"error connecting to peer");
            [self disconnect];
            break;
            
        case NSStreamEventEndEncountered:
            NSLog(@"peer connection closed");
            [self disconnect];
            break;
            
        default:
            NSLog(@"unknown network stream event");
    }
}

@end

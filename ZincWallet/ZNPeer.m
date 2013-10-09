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
#import "NSStream+Bitcoin.h"
#import <arpa/inet.h>

#define ENABLED_SERVICES       0 // we don't provide full blocks to remote nodes
#define PROTOCOL_VERSION       70001
#define MIN_PROTO_VERSION      209 // peers earlier than this protocol version not supported
#define LOCAL_HOST             0x010000ff
#define REFERENCE_BLOCK_HEIGHT 250000
#define USERAGENT [NSString stringWithFormat:@"/zincwallet:%@/", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]]

#define FNV32_PRIME  0x01000193u
#define FNV32_OFFSET 0x811C9DC5u

#define llurand() (((long long unsigned)mrand48() << (sizeof(unsigned)*8)) | (unsigned)mrand48())

@interface ZNPeer ()

@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableData *inputBuffer;

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
    
    self.inputBuffer = [NSMutableData data];
    
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

- (NSInteger)sendVersion
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
    [d appendUInt32:REFERENCE_BLOCK_HEIGHT]; // last block received //TODO: XXXX get last block stored in core data
    [d appendUInt8:0]; // relay transactions (no for SPV bloom filter mode)
    
    return [self.outputStream writeCommand:@"version" payload:d];
}

#pragma mark - hash

- (NSUInteger)hash
{
    // FNV32-1a hash of the ip address and port number: http://www.isthe.com/chongo/tech/comp/fnv/index.html#FNV-1a
    uint32_t hash = FNV32_OFFSET;
    
    hash = (hash^((self.address >> 24) & 0xFF))*FNV32_PRIME;
    hash = (hash^((self.address >> 16) & 0xFF))*FNV32_PRIME;
    hash = (hash^((self.address >> 8) & 0xFF))*FNV32_PRIME;
    hash = (hash^(self.address & 0xFF))*FNV32_PRIME;
    hash = (hash^((self.port >> 8) & 0xFF))*FNV32_PRIME;
    return (hash^(self.port & 0xFF))*FNV32_PRIME;
}

- (BOOL)isEqual:(id)object
{
    return [object isKindOfClass:[ZNPeer class]] &&
           self.address == [(ZNPeer *)object address] && self.port == [(ZNPeer *)object port];
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    NSInteger l = 0;
    
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"Stream opened");
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (aStream != self.inputStream) break;

            while ([(NSInputStream *)aStream hasBytesAvailable]) {
                self.inputBuffer.length += 1024;
                l = [(NSInputStream *)aStream read:self.inputBuffer.mutableBytes maxLength:1024];
                
                if (l <= 0) {
                    self.inputBuffer.length -= 1024;
                    continue;
                }
                
                self.inputBuffer.length -= 1024 - l;
                
                if (self.inputBuffer.length < BITCOIN_MSG_HEADER_LENGTH) continue;
                    
                //NSString *output = [[NSString alloc] initWithBytes:buffer length:l encoding:NSUTF8StringEncoding];
                
                //NSLog(@"server said: %@", output);
                
                // if we get a version msg, send verack
                
                // if we get a verack, we know the peer accepted our version msg
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

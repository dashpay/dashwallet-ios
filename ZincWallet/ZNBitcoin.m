//
//  ZNBitcoin.m
//  ZincWallet
//
//  Created by Aaron Voisine on 10/6/13.
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

#import "ZNBitcoin.h"
#import "ZNPeerEntity.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Hash.h"
#import "NSManagedObject+Utils.h"
#import <netdb.h>
#import <arpa/inet.h>

#define USERAGENT [NSString stringWithFormat:@"/zincwallet:%@/", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]]
#define MAX_CONNECTIONS 3
#define FIXED_PEERS     @"FixedPeers"

#if BITCOIN_TESTNET
#define STANDARD_PORT   18333
#define MAGIC_NUMBER    "\x0B\x11\x09\x07"
#else // BITCOIN_TESTNET
#define STANDARD_PORT   8333
#define MAGIC_NUMBER    "\xF9\xBE\xB4\xD9"
#endif // BITCOIN_TESTNET

@interface ZNBitcoin ()

@property (nonatomic, strong) NSMutableArray *peers, *inStreams, *outStreams;

@end

@implementation ZNBitcoin

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });
    
    return singleton;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;

    self.peers = [NSMutableArray array];
    self.inStreams = [NSMutableArray array];
    self.outStreams = [NSMutableArray array];
    
    return self;
}

- (NSUInteger)discoverPeers
{
    __block NSUInteger count = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970;
#if BITCOIN_TESTNET
    NSArray *a = @[@"testnet-seed.bitcoin.petertodd.org", @"testnet-seed.bluematt.me"];
#else
    NSArray *a = @[@"seed.bitcoin.sipa.be", @"dnsseed.bluematt.me", @"dnsseed.bitcoin.dashjr.org", @"bitseed.xf2.org"];
#endif

    // DNS peer discovery
    // TODO: provide seed.zincwallet.com DNS seed service
    [a enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        struct hostent *h = gethostbyname([obj UTF8String]);
        
        for (int j = 0; h->h_addr_list[j] != NULL; j++) {
            struct in_addr a = *(struct in_addr *)h->h_addr_list[j];
            NSTimeInterval t = now - 24*60*60*(3 + drand48()*4); // random timestamp between 3 and 7 days ago
            
            [ZNPeerEntity entityWithAddress:a.s_addr port:STANDARD_PORT timestamp:t services:0];
            count++;
        }
    }];
    
#if ! BITCOIN_TESTNET
    if (count > 0) return count;
     
    // if dns peer discovery fails, fall back on a hard coded list of peers
    [[NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:FIXED_PEERS ofType:@"plist"]]
    enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSTimeInterval t = now - 24*60*60*(7 + drand48()*7); // random timestamp between 7 and 14 days ago
        
        [ZNPeerEntity entityWithAddress:[obj intValue] port:STANDARD_PORT timestamp:t services:0];
        count++;
    }];
#endif
    
    return count;
}

- (ZNPeerEntity *)randomPeer
{
    NSUInteger count = [ZNPeerEntity countAllObjects], offset = 0;
    
    if (count == 0) count += [self discoverPeers];
    if (count == 0) return nil;
    
    offset = pow(random() % count, 2)/count; // pick a random peer with bias toward peers with more recent timestamps
    return [ZNPeerEntity objectsSortedBy:@"timestamp" ascending:NO offset:offset limit:1].lastObject;
}

- (void)connect
{
    ZNPeerEntity *peer = [self randomPeer];
    
    if (! peer) return;
    
    struct in_addr addr = { peer.address };
    NSString *host = [NSString stringWithUTF8String:inet_ntoa(addr)];
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;

    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host, peer.port, &readStream, &writeStream);

    NSInputStream *inStream = CFBridgingRelease(readStream);
    NSOutputStream *outStream = CFBridgingRelease(writeStream);

    inStream.delegate = outStream.delegate = self;
    
    // we may want to use a different thread for each peer
    [inStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    [self.peers addObject:peer];
    [self.inStreams addObject:inStream];
    [self.outStreams addObject:outStream];
    
    [inStream open];
    [outStream open];

    //send version message
    [self sendVersion:outStream];

    // send msg
    //NSString *response  = [NSString stringWithFormat:@"msg:%@", inputMessageField.text];
    //NSData *data = [[NSData alloc] initWithData:[response dataUsingEncoding:NSASCIIStringEncoding]];
    //[outputStream write:[data bytes] maxLength:[data length]];
}

- (void)sendCommand:(NSString *)command payload:(NSData *)payload stream:(NSOutputStream *)stream
{
    uint32_t l = CFSwapInt32HostToLittle((uint32_t)payload.length);
    
    [stream write:(const uint8_t *)MAGIC_NUMBER maxLength:strlen(MAGIC_NUMBER)];
    [stream write:(const uint8_t *)command.UTF8String
     maxLength:[command lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    [stream write:(const uint8_t *)"\0\0\0\0\0\0\0\0\0\0\0\0"
     maxLength:12 - [command lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    [stream write:(const uint8_t *)&l maxLength:sizeof(uint32_t)];
    [stream write:[[payload SHA256_2] bytes] maxLength:4];
    [stream write:payload.bytes maxLength:payload.length];
}

- (void)sendVersion:(NSOutputStream *)outStream
{
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    uint8_t buffer[1024];

    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"Stream opened");
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (! [self.inStreams containsObject:aStream]) break;
            
            while ([(NSInputStream *)aStream hasBytesAvailable]) {
                NSInteger l = [(NSInputStream *)aStream read:buffer maxLength:sizeof(buffer)];
                
                if (l <= 0) continue;
                
                NSString *output = [[NSString alloc] initWithBytes:buffer length:l encoding:NSUTF8StringEncoding];
                
                NSLog(@"server said: %@", output);
                
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

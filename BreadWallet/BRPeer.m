//
//  BRPeer.m
//  BreadWallet
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

#import "BRPeer.h"
#import "BRTransaction.h"
#import "BRMerkleBlock.h"
#import "NSMutableData+Bitcoin.h"
#import "NSString+Base58.h"
#import "NSData+Bitcoin.h"
#import "NSData+Hash.h"
#import <arpa/inet.h>
#import "Reachability.h"

#define USERAGENT [NSString stringWithFormat:@"/breadwallet:%@/",NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]]

#define HEADER_LENGTH      24
#define MAX_MSG_LENGTH     0x02000000
#define MAX_GETDATA_HASHES 50000
#define ENABLED_SERVICES   0     // we don't provide full blocks to remote nodes
#define PROTOCOL_VERSION   70002
#if TX_FEE_0_8_RULES
#define MIN_PROTO_VERSION  70001 // peers earlier than this protocol version not supported (SPV mode required)
#else
#define MIN_PROTO_VERSION  70002 // peers earlier than this protocol version not supported (need v0.9 txFee relay rules)
#endif
#define LOCAL_HOST         0x7f000001
#define ZERO_HASH          @"0000000000000000000000000000000000000000000000000000000000000000".hexToData
#define CONNECT_TIMEOUT    3.0

typedef enum {
    error = 0,
    tx,
    block,
    merkleblock
} inv_t;

@interface BRPeer ()

@property (nonatomic, assign) id<BRPeerDelegate> delegate;
@property (nonatomic, strong) dispatch_queue_t delegateQueue;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableData *msgHeader, *msgPayload, *outputBuffer;
@property (nonatomic, assign) BOOL sentVerack, gotVerack;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) id reachabilityObserver;
@property (nonatomic, assign) uint64_t localNonce;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, strong) BRMerkleBlock *currentBlock;
@property (nonatomic, strong) NSMutableOrderedSet *currentBlockHashes, *currentTxHashes, *knownTxHashes;
@property (nonatomic, strong) NSCountedSet *requestedBlockHashes;
@property (nonatomic, assign) uint32_t filterBlockCount;
@property (nonatomic, strong) NSRunLoop *runLoop;

@end

@implementation BRPeer

@dynamic host;

+ (instancetype)peerWithAddress:(uint32_t)address andPort:(uint16_t)port
{
    return [[self alloc] initWithAddress:address andPort:port];
}

- (instancetype)initWithAddress:(uint32_t)address andPort:(uint16_t)port
{
    if (! (self = [self init])) return nil;
    
    _address = address;
    _port = (port == 0) ? BITCOIN_STANDARD_PORT : port;
    return self;
}

- (instancetype)initWithAddress:(uint32_t)address port:(uint16_t)port timestamp:(NSTimeInterval)timestamp
services:(uint64_t)services
{
    if (! (self = [self initWithAddress:address andPort:port])) return nil;
    
    _timestamp = timestamp;
    _services = services;
    return self;
}

- (void)dealloc
{
    [self.reachability stopNotifier];
    if (self.reachabilityObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)setDelegate:(id<BRPeerDelegate>)delegate queue:(dispatch_queue_t)delegateQueue
{
    _delegate = delegate;
    _delegateQueue = delegateQueue;
}

- (NSString *)host
{
    struct in_addr addr = { CFSwapInt32HostToBig(self.address) };
    char s[INET_ADDRSTRLEN];

    return [NSString stringWithUTF8String:inet_ntop(AF_INET, &addr, s, INET_ADDRSTRLEN)];
}

- (void)connect
{
    if (self.status != BRPeerStatusDisconnected) return;
    if (! self.delegateQueue) _delegateQueue = dispatch_get_main_queue();
    if (! self.reachability) self.reachability = [Reachability reachabilityWithHostName:self.host];
    
    if (self.reachability.currentReachabilityStatus == NotReachable) { // delay connect until network is reachable
        if (self.reachabilityObserver) return;
        
        self.reachabilityObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification
            object:self.reachability queue:nil usingBlock:^(NSNotification *note) {
                if (self.reachability.currentReachabilityStatus != NotReachable) [self connect];
            }];
        
        [self.reachability startNotifier];
    }
    else if (self.reachabilityObserver) {
        [self.reachability stopNotifier];
        [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
        self.reachabilityObserver = nil;
    }

    _status = BRPeerStatusConnecting;
    _pingTime = DBL_MAX;
    self.msgHeader = [NSMutableData data];
    self.msgPayload = [NSMutableData data];
    self.outputBuffer = [NSMutableData data];
    self.knownTxHashes = [NSMutableOrderedSet orderedSet];
    self.currentBlockHashes = [NSMutableOrderedSet orderedSet];
    self.requestedBlockHashes = [NSCountedSet set];

    NSString *label = [NSString stringWithFormat:@"peer.%@:%d", self.host, self.port];

    // use a private serial queue for processing socket io
    dispatch_async(dispatch_queue_create(label.UTF8String, NULL), ^{
        CFReadStreamRef readStream = NULL;
        CFWriteStreamRef writeStream = NULL;

        NSLog(@"%@:%u connecting", self.host, self.port);
    
        CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.host, self.port, &readStream, &writeStream);
        self.inputStream = CFBridgingRelease(readStream);
        self.outputStream = CFBridgingRelease(writeStream);
        self.inputStream.delegate = self.outputStream.delegate = self;

        self.runLoop = [NSRunLoop currentRunLoop];
        [self.inputStream scheduleInRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
        [self.outputStream scheduleInRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
        
        // after the reachablity check, the radios should be warmed up and we can set a short socket connect timeout
        [self performSelector:@selector(disconnectWithError:) withObject:[NSError errorWithDomain:@"BreadWallet"
         code:BITCOIN_TIMEOUT_CODE userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"connect timeout", nil)}]
         afterDelay:CONNECT_TIMEOUT];
        
        [self.inputStream open];
        [self.outputStream open];
    
        [self sendVersionMessage];
        [self.runLoop run]; // this doesn't return until the runloop is stopped
    });
}

- (void)disconnect
{
    [self disconnectWithError:nil];
}

- (void)disconnectWithError:(NSError *)error
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel connect timeout
    
    _status = BRPeerStatusDisconnected;

    if (self.reachabilityObserver) { //BUG: XXXX causing exec_bad_access for info in ReachabilityCallback line 90 ?
        [self.reachability stopNotifier];
        [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
        self.reachabilityObserver = nil;
    }

    if (! self.runLoop) return;
    
    // can't use dispatch_async here because the runloop blocks the queue, so schedule on the runloop instead
    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        [self.inputStream close];
        [self.outputStream close];

        [self.inputStream removeFromRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
        [self.outputStream removeFromRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
        
        CFRunLoopStop([self.runLoop getCFRunLoop]);
        
        self.gotVerack = self.sentVerack = NO;
        _status = BRPeerStatusDisconnected;
        dispatch_async(self.delegateQueue, ^{
            [self.delegate peer:self disconnectedWithError:error];
        });
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

- (void)error:(NSString *)message, ...
{
    va_list args;

    va_start(args, message);
    [self disconnectWithError:[NSError errorWithDomain:@"BreadWallet" code:500
     userInfo:@{NSLocalizedDescriptionKey:[[NSString alloc] initWithFormat:message arguments:args]}]];
    va_end(args);
}

- (void)didConnect
{
    if (self.status != BRPeerStatusConnecting || ! self.sentVerack || ! self.gotVerack) return;

    NSLog(@"%@:%d handshake completed", self.host, self.port);
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel pending handshake timeout
    _status = BRPeerStatusConnected;
    dispatch_async(self.delegateQueue, ^{
        if (_status == BRPeerStatusConnected) [self.delegate peerConnected:self];
    });
}

#pragma mark - send

- (void)sendMessage:(NSData *)message type:(NSString *)type
{
    if (message.length > MAX_MSG_LENGTH) {
        NSLog(@"%@:%d failed to send %@, length %d is too long", self.host, self.port, type, (int)message.length);
#if DEBUG
        abort();
#endif
        return;
    }

    if (! self.runLoop) return;

    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        NSLog(@"%@:%d sending %@", self.host, self.port, type);

        [self.outputBuffer appendMessage:message type:type];
        
        while (self.outputBuffer.length > 0 && [self.outputStream hasSpaceAvailable]) {
            NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];

            if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
            //if (self.outputBuffer.length == 0) NSLog(@"%@:%d output buffer cleared", self.host, self.port);
        }
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

- (void)sendVersionMessage
{
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendUInt32:PROTOCOL_VERSION]; // version
    [msg appendUInt64:ENABLED_SERVICES]; // services
    [msg appendUInt64:[NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970]; // timestamp
    [msg appendNetAddress:self.address port:self.port services:self.services]; // address of remote peer
    [msg appendNetAddress:LOCAL_HOST port:BITCOIN_STANDARD_PORT services:ENABLED_SERVICES]; // address of local peer
    self.localNonce = (((uint64_t)mrand48() << 32) | (uint32_t)mrand48()); // random nonce
    [msg appendUInt64:self.localNonce];
    [msg appendString:USERAGENT]; // user agent
    [msg appendUInt32:0]; // last block received
    [msg appendUInt8:0]; // relay transactions (no for SPV bloom filter mode)

    self.startTime = [NSDate timeIntervalSinceReferenceDate];
    [self sendMessage:msg type:MSG_VERSION];
}

- (void)sendVerackMessage
{
    [self sendMessage:[NSData data] type:MSG_VERACK];
    self.sentVerack = YES;
    [self didConnect];
}

- (void)sendFilterloadMessage:(NSData *)filter
{
    self.filterBlockCount = 0;
    [self sendMessage:filter type:MSG_FILTERLOAD];
}

- (void)sendMempoolMessage
{
    [self sendMessage:[NSData data] type:MSG_MEMPOOL];
}

- (void)sendAddrMessage
{
    NSMutableData *msg = [NSMutableData data];
    
    //TODO: send peer addresses we know about
    [msg appendVarInt:0];
    [self sendMessage:msg type:MSG_ADDR];
}

// the standard blockchain download protocol works as follows (for SPV mode):
// - local peer sends getblocks
// - remote peer reponds with inv containing up to 500 block hashes
// - local peer sends getdata with the block hashes
// - remote peer responds with multiple merkleblock and tx messages
// - remote peer sends inv containg 1 hash, of the most recent block
// - local peer sends getdata with the most recent block hash
// - remote peer responds with merkleblock
// - if local peer can't connect the most recent block to the chain (because it started more than 500 blocks behind), go
//   back to first step and repeat until entire chain is downloaded
//
// we modify this sequence to improve sync performance and handle adding bip32 addresses to the bloom filter as needed:
// - local peer sends getheaders
// - remote peer responds with up to 2000 headers
// - local peer immediately sends getheaders again and then processes the headers
// - previous two steps repeat until a header within a week of earliestKeyTime is reached (further headers are ignored)
// - local peer sends getblocks
// - remote peer responds with inv containing up to 500 block hashes
// - if there are 500, local peer immediately sends getblocks again, followed by getdata with the block hashes
// - remote peer responds with inv containing up to 500 block hashes, followed by multiple merkleblock and tx messages
// - previous two steps repeat until an inv with fewer than 500 block hashes is received
// - local peer sends just getdata for the final set of fewer than 500 block hashes
// - remote peer responds with multiple merkleblock and tx messages
// - if at any point tx messages consume enough wallet addresses to drop below the bip32 chain gap limit, more addresses
//   are generated and local peer sends filterload with an updated bloom filter
// - after filterload is sent, getdata is sent to re-request recent blocks that may contain new tx matching the filter

- (void)sendGetheadersMessageWithLocators:(NSArray *)locators andHashStop:(NSData *)hashStop
{
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendUInt32:PROTOCOL_VERSION];
    [msg appendVarInt:locators.count];
    
    for (NSData *hash in locators) {
        [msg appendData:hash];
    }
    
    [msg appendData:hashStop ? hashStop : ZERO_HASH];
    NSLog(@"%@:%u calling getheaders with locators: %@", self.host, self.port,
          @[locators.firstObject, locators.lastObject]);
    [self sendMessage:msg type:MSG_GETHEADERS];
}

- (void)sendGetblocksMessageWithLocators:(NSArray *)locators andHashStop:(NSData *)hashStop
{
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendUInt32:PROTOCOL_VERSION];
    [msg appendVarInt:locators.count];

    for (NSData *hash in locators) {
        [msg appendData:hash];
    }
    
    [msg appendData:hashStop ? hashStop : ZERO_HASH];
    [self sendMessage:msg type:MSG_GETBLOCKS];
}

- (void)sendInvMessageWithTxHash:(NSData *)txHash
{
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendVarInt:1];
    [msg appendUInt32:tx];
    [msg appendData:txHash];
    [self sendMessage:msg type:MSG_INV];
    [self.knownTxHashes addObject:txHash];
}

- (void)sendGetdataMessageWithTxHashes:(NSArray *)txHashes andBlockHashes:(NSArray *)blockHashes
{
    if (txHashes.count + blockHashes.count > MAX_GETDATA_HASHES) { // limit total hash count to MAX_GETDATA_HASHES
        NSLog(@"%@:%d couldn't send getdata, %u is too many items, max is %u", self.host, self.port,
              (int)txHashes.count + (int)blockHashes.count, MAX_GETDATA_HASHES);
        return;
    }
    
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendVarInt:txHashes.count + blockHashes.count];
    
    for (NSData *hash in txHashes) {
        [msg appendUInt32:tx];
        [msg appendData:hash];
    }
    
    for (NSData *hash in blockHashes) {
        [msg appendUInt32:merkleblock];
        [msg appendData:hash];
    }

    [self.requestedBlockHashes addObjectsFromArray:blockHashes];

    if (self.filterBlockCount + blockHashes.count > BLOCK_DIFFICULTY_INTERVAL) {
        NSLog(@"%@:%d rebuilding bloom filter after %d blocks", self.host, self.port, self.filterBlockCount);
        [self sendFilterloadMessage:[self.delegate peerBloomFilter:self]];
    }

    self.filterBlockCount += (uint32_t)blockHashes.count;
    [self sendMessage:msg type:MSG_GETDATA];
}

- (void)sendGetaddrMessage
{
    [self sendMessage:[NSData data] type:MSG_GETADDR];
}

- (void)sendPingMessage
{
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendUInt64:self.localNonce];
    self.startTime = [NSDate timeIntervalSinceReferenceDate];
    [self sendMessage:msg type:MSG_PING];
}

// re-request blocks starting from blockHash, useful for getting any additional transactions after a bloom filter update
- (void)rereqeustBlocksFrom:(NSData *)blockHash
{
    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        NSUInteger i = [self.currentBlockHashes indexOfObject:blockHash];

        if (i != NSNotFound) {
            [self.currentBlockHashes removeObjectsInRange:NSMakeRange(0, i)];
            NSLog(@"%@:%d re-requesting %d blocks", self.host, self.port, (int)self.currentBlockHashes.count);
            [self sendGetdataMessageWithTxHashes:@[] andBlockHashes:self.currentBlockHashes.array];
        }
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

#pragma mark - accept

- (void)acceptMessage:(NSData *)message type:(NSString *)type
{
    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        if (self.currentBlock && ! [MSG_TX isEqual:type]) { // if we receive a non-tx message, the merkleblock is done
            self.currentBlock = nil;
            self.currentTxHashes = nil;
            [self error:@"incomplete merkleblock %@, expected %u more tx", self.currentBlock.blockHash,
             (int)self.currentTxHashes.count];
            return;
        }

        if ([MSG_VERSION isEqual:type]) [self acceptVersionMessage:message];
        else if ([MSG_VERACK isEqual:type]) [self acceptVerackMessage:message];
        else if ([MSG_ADDR isEqual:type]) [self acceptAddrMessage:message];
        else if ([MSG_INV isEqual:type]) [self acceptInvMessage:message];
        else if ([MSG_TX isEqual:type]) [self acceptTxMessage:message];
        else if ([MSG_HEADERS isEqual:type]) [self acceptHeadersMessage:message];
        else if ([MSG_GETADDR isEqual:type]) [self acceptGetaddrMessage:message];
        else if ([MSG_GETDATA isEqual:type]) [self acceptGetdataMessage:message];
        else if ([MSG_NOTFOUND isEqual:type]) [self acceptNotfoundMessage:message];
        else if ([MSG_PING isEqual:type]) [self acceptPingMessage:message];
        else if ([MSG_PONG isEqual:type]) [self acceptPongMessage:message];
        else if ([MSG_MERKLEBLOCK isEqual:type]) [self acceptMerkleblockMessage:message];
        else if ([MSG_REJECT isEqual:type]) [self acceptRejectMessage:message];
        else NSLog(@"%@:%d dropping %@, length %u, not implemented", self.host, self.port, type, (int)message.length);
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

- (void)acceptVersionMessage:(NSData *)message
{
    NSUInteger l = 0;
    
    if (message.length < 85) {
        [self error:@"malformed version message, length is %u, should be > 84", (int)message.length];
        return;
    }
    
    _version = [message UInt32AtOffset:0];
    
    if (self.version < MIN_PROTO_VERSION) {
        [self error:@"protocol version %u not supported", self.version];
        return;
    }
    
    _services = [message UInt64AtOffset:4];
    _timestamp = [message UInt64AtOffset:12] - NSTimeIntervalSince1970;
    _useragent = [message stringAtOffset:80 length:&l];

    if (message.length < 80 + l + sizeof(uint32_t)) {
        [self error:@"malformed version message, length is %u, should be %lu", (int)message.length, 80 + l + 4];
        return;
    }
    
    _lastblock = [message UInt32AtOffset:80 + l];
    
    NSLog(@"%@:%d got version %d, useragent:\"%@\"", self.host, self.port, self.version, self.useragent);
    
    [self sendVerackMessage];
}

- (void)acceptVerackMessage:(NSData *)message
{
    if (self.gotVerack) {
        NSLog(@"%@:%d got unexpected verack", self.host, self.port);
        return;
    }
    
    _pingTime = [NSDate timeIntervalSinceReferenceDate] - self.startTime; // use verack time as initial ping time
    self.startTime = 0;
    
    NSLog(@"%@:%u got verack in %fs", self.host, self.port, self.pingTime);
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel pending verack timeout
    self.gotVerack = YES;
    [self didConnect];
}

//NOTE: since we connect only intermitently, a hostile node could flush the address list with bad values that would take
// several minutes to clear, after which we would fall back on DNS seeding.
// TODO: keep around at least 1000 nodes we've personally connected to.
// TODO: relay addresses
- (void)acceptAddrMessage:(NSData *)message
{
    if (message.length > 0 && [message UInt8AtOffset:0] == 0) {
        NSLog(@"%@:%d got addr with 0 addresses", self.host, self.port);
        return;
    }
    else if (message.length < 5) {
        [self error:@"malformed addr message, length %u is too short", (int)message.length];
        return;
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSUInteger l, count = (NSUInteger)[message varIntAtOffset:0 length:&l];
    NSMutableArray *peers = [NSMutableArray array];
    
    if (count > 1000) {
        NSLog(@"%@:%d dropping addr message, %u is too many addresses (max 1000)", self.host, self.port, (int)count);
        return;
    }
    else if (message.length < l + count*30) {
        [self error:@"malformed addr message, length is %u, should be %u for %u addresses", (int)message.length,
         (int)(l + count*30), (int)count];
        return;
    }
    else NSLog(@"%@:%d got addr with %u addresses", self.host, self.port, (int)count);
    
    for (NSUInteger off = l; off < l + 30*count; off += 30) {
        NSTimeInterval timestamp = [message UInt32AtOffset:off] - NSTimeIntervalSince1970;
        uint64_t services = [message UInt64AtOffset:off + sizeof(uint32_t)];
        uint32_t address = CFSwapInt32BigToHost(*(const uint32_t *)((const uint8_t *)message.bytes + off +
                                                                    sizeof(uint32_t) + 20));
        uint16_t port = CFSwapInt16BigToHost(*(const uint16_t *)((const uint8_t *)message.bytes + off +
                                                                 sizeof(uint32_t)*2 + 20));
        
        // if address time is more than 10 min in the future or older than reference date, set to 5 days old
        if (timestamp > now + 10*60 || timestamp < 0) timestamp = now - 5*24*60*60;

        // subtract two hours and add it to the list
        [peers addObject:[[BRPeer alloc] initWithAddress:address port:port timestamp:timestamp - 2*60*60
         services:services]];
    }

    dispatch_async(self.delegateQueue, ^{
        if (_status == BRPeerStatusConnected) [self.delegate peer:self relayedPeers:peers];
    });
}

- (void)acceptInvMessage:(NSData *)message
{
    NSUInteger l, count = (NSUInteger)[message varIntAtOffset:0 length:&l];
    NSMutableOrderedSet *txHashes = [NSMutableOrderedSet orderedSet], *blockHashes = [NSMutableOrderedSet orderedSet];
    
    if (l == 0 || message.length < l + count*36) {
        [self error:@"malformed inv message, length is %u, should be %u for %u items", (int)message.length,
         (int)((l == 0) ? 1 : l) + (int)count*36, (int)count];
        return;
    }
    else if (count > MAX_GETDATA_HASHES) {
        NSLog(@"%@:%u dropping inv message, %u is too many items, max is %d", self.host, self.port, (int)count,
              MAX_GETDATA_HASHES);
        return;
    }
    
    for (NSUInteger off = l; off < l + 36*count; off += 36) {
        inv_t type = [message UInt32AtOffset:off];
        NSData *hash = [message hashAtOffset:off + sizeof(uint32_t)];
        
        if (! hash) continue;
        
        switch (type) {
            case tx: [txHashes addObject:hash]; break;
            case block: [blockHashes addObject:hash]; break;
            case merkleblock: [blockHashes addObject:hash]; break;
            default: break;
        }
    }

    NSLog(@"%@:%u got inv with %u items", self.host, self.port, (int)count);

    if (txHashes.count > 10000) { // this was happening on testnet, some sort of DOS/spam attack?
        NSLog(@"%@:%u too many transactions, disconnecting", self.host, self.port);
        [self disconnect]; // disconnecting seems to be the easiest way to mitigate it
        return;
    }

    // to improve chain download performance, if we received 500 block hashes, we request the next 500 block hashes
    // immediately before sending the getdata request
    if (blockHashes.count >= 500) {
        [self sendGetblocksMessageWithLocators:@[blockHashes.lastObject, blockHashes.firstObject] andHashStop:nil];
    }

    [txHashes minusOrderedSet:self.knownTxHashes];
    [self.knownTxHashes unionOrderedSet:txHashes];
    
    if (txHashes.count + blockHashes.count > 0) {
        [self sendGetdataMessageWithTxHashes:txHashes.array andBlockHashes:blockHashes.array];

        // Each merkleblock the remote peer sends us is followed by a set of tx messages for that block. We send a ping
        // to get a pong reply after the block and all its tx are sent, inicating that there are no more tx messages
        if (blockHashes.count == 1) [self sendPingMessage];
    }

    if (blockHashes.count > 0) { // remember blockHashes in case we need to re-request them with an updated bloom filter
        [self.currentBlockHashes unionOrderedSet:blockHashes];
        if (self.currentBlockHashes.count > MAX_GETDATA_HASHES) {
            [self.currentBlockHashes
             removeObjectsInRange:NSMakeRange(0, self.currentBlockHashes.count - MAX_GETDATA_HASHES/2)];
        }
    }
}

- (void)acceptTxMessage:(NSData *)message
{
    BRTransaction *tx = [BRTransaction transactionWithMessage:message];
    
    if (! tx) {
        [self error:@"malformed tx message: %@", message];
        return;
    }
    
    NSLog(@"%@:%u got tx %@", self.host, self.port, tx.txHash);

    dispatch_async(self.delegateQueue, ^{
        if (_status == BRPeerStatusConnected) [self.delegate peer:self relayedTransaction:tx];
    });

    if (self.currentBlock) { // we're collecting tx messages for a merkleblock
        [self.currentTxHashes removeObject:tx.txHash];

        if (self.currentTxHashes.count == 0) { // we received the entire block including all matched tx
            BRMerkleBlock *block = self.currentBlock;

            self.currentBlock = nil;
            self.currentTxHashes = nil;

            dispatch_async(self.delegateQueue, ^{
                if (_status == BRPeerStatusConnected) [self.delegate peer:self relayedBlock:block];
            });
        }
    }
}

- (void)acceptHeadersMessage:(NSData *)message
{
    NSUInteger l, count = (NSUInteger)[message varIntAtOffset:0 length:&l], off;
    
    if (message.length < l + 81*count) {
        [self error:@"malformed headers message, length is %u, should be %u for %u items", (int)message.length,
         (int)((l == 0) ? 1 : l) + (int)count*81, (int)count];
        return;
    }

    // To improve chain download performance, if this message contains 2000 headers then request the next 2000 headers
    // immediately, and switching to requesting blocks when we receive a header newer than earliestKeyTime
    NSTimeInterval t = [message UInt32AtOffset:l + 81*(count - 1) + 68] - NSTimeIntervalSince1970;

    if (count >= 2000 || t + 7*24*60*60 >= self.earliestKeyTime - 2*60*60) {
        NSData *firstHash = [message subdataWithRange:NSMakeRange(l, 80)].SHA256_2,
               *lastHash = [message subdataWithRange:NSMakeRange(l + 81*(count - 1), 80)].SHA256_2;

        if (t + 7*24*60*60 >= self.earliestKeyTime - 2*60*60) { // request blocks for the remainder of the chain
            t = [message UInt32AtOffset:l + 81 + 68] - NSTimeIntervalSince1970;

            for (off = l; t > 0 && t + 7*24*60*60 < self.earliestKeyTime;) {
                off += 81;
                t = [message UInt32AtOffset:off + 81 + 68] - NSTimeIntervalSince1970;
            }

            lastHash = [message subdataWithRange:NSMakeRange(off, 80)].SHA256_2;

            NSLog(@"%@:%u calling getblocks with locators: %@", self.host, self.port, @[lastHash, firstHash]);
            [self sendGetblocksMessageWithLocators:@[lastHash, firstHash] andHashStop:nil];
        }
        else [self sendGetheadersMessageWithLocators:@[lastHash, firstHash] andHashStop:nil];
    }

    NSLog(@"%@:%u got %u headers", self.host, self.port, (int)count);
    
    // schedule this on the runloop to ensure the above get message is sent first for faster chain download
    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        for (NSUInteger off = l; off < l + 81*count; off += 81) {
            BRMerkleBlock *block = [BRMerkleBlock blockWithMessage:[message subdataWithRange:NSMakeRange(off, 81)]];
    
            if (! block.valid) {
                [self error:@"invalid block header %@", block.blockHash];
                return;
            }

            dispatch_async(self.delegateQueue, ^{
                if (_status == BRPeerStatusConnected) [self.delegate peer:self relayedBlock:block];
            });
        }
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

- (void)acceptGetaddrMessage:(NSData *)message
{
    NSLog(@"%@:%u got getaddr", self.host, self.port);
    
    [self sendAddrMessage];
}

- (void)acceptGetdataMessage:(NSData *)message
{
    NSUInteger l, count = (NSUInteger)[message varIntAtOffset:0 length:&l];
    
    if (l == 0 || message.length < l + count*36) {
        [self error:@"malformed getdata message, length is %u, should be %u for %u items", (int)message.length,
         (int)((l == 0) ? 1 : l) + (int)count*36, (int)count];
        return;
    }
    else if (count > MAX_GETDATA_HASHES) {
        NSLog(@"%@:%u dropping getdata message, %u is too many items, max is %d", self.host, self.port, (int)count,
              MAX_GETDATA_HASHES);
        return;
    }
    
    NSLog(@"%@:%u got getdata with %u items", self.host, self.port, (int)count);

    dispatch_async(self.delegateQueue, ^{
        NSMutableData *notfound = [NSMutableData data];
    
        for (NSUInteger off = l; off < l + count*36; off += 36) {
            inv_t type = [message UInt32AtOffset:off];
            NSData *hash = [message hashAtOffset:off + sizeof(uint32_t)];
            BRTransaction *transaction = nil;
        
            if (! hash) continue;
        
            switch (type) {
                case tx:
                    transaction = [self.delegate peer:self requestedTransaction:hash];
                
                    if (transaction) {
                        [self sendMessage:transaction.data type:MSG_TX];
                        break;
                    }
                
                    // fall through
                default:
                    [notfound appendUInt32:type];
                    [notfound appendData:hash];
                    break;
            }
        }

        if (notfound.length > 0) {
            NSMutableData *msg = [NSMutableData data];
        
            [msg appendVarInt:notfound.length/36];
            [msg appendData:notfound];
            [self sendMessage:msg type:MSG_NOTFOUND];
        }
    });
}

- (void)acceptNotfoundMessage:(NSData *)message
{
    NSUInteger l, count = (NSUInteger)[message varIntAtOffset:0 length:&l];

    if (l == 0 || message.length < l + count*36) {
        [self error:@"malformed notfount message, length is %u, should be %u for %u items", (int)message.length,
         (int)((l == 0) ? 1 : l) + (int)count*36, (int)count];
        return;
    }

    NSLog(@"%@:%u got notfound with %u items", self.host, self.port, (int)count);
}

- (void)acceptPingMessage:(NSData *)message
{
    if (message.length < sizeof(uint64_t)) {
        [self error:@"malformed ping message, length is %u, should be 4", (int)message.length];
        return;
    }
    
    NSLog(@"%@:%u got ping", self.host, self.port);
    
    [self sendMessage:message type:MSG_PONG];
}

- (void)acceptPongMessage:(NSData *)message
{
    if (message.length < sizeof(uint64_t)) {
        [self error:@"malformed pong message, length is %u, should be 4", (int)message.length];
        return;
    }
    else if ([message UInt64AtOffset:0] != self.localNonce) {
        [self error:@"pong message contained wrong nonce: %llu, expected: %llu", [message UInt64AtOffset:0],
         self.localNonce];
        return;
    }
    else if (self.startTime < 1) {
        NSLog(@"%@:%d got unexpected pong", self.host, self.port);
        return;
    }

    NSTimeInterval pingTime = [NSDate timeIntervalSinceReferenceDate] - self.startTime;
    
    // 50% low pass filter on current ping time
    _pingTime = self.pingTime*0.5 + pingTime*0.5;
    self.startTime = 0;
    
    NSLog(@"%@:%u got pong in %fs", self.host, self.port, self.pingTime);
}

- (void)acceptMerkleblockMessage:(NSData *)message
{
    // Bitcoin nodes don't support querying arbitrary transactions, only transactions not yet accepted in a block. After
    // a merkleblock message, the remote node is expected to send tx messages for the tx referenced in the block. When a
    // non-tx message is received we should have all the tx in the merkleblock.

    BRMerkleBlock *block = [BRMerkleBlock blockWithMessage:message];
    
    if (! block.valid) {
        [self error:@"invalid merkleblock: %@", block.blockHash];
        return;
    }
    //else NSLog(@"%@:%u got merkleblock %@", self.host, self.port, block.blockHash);

    [self.requestedBlockHashes removeObject:block.blockHash];
    if ([self.requestedBlockHashes countForObject:block.blockHash] > 0) {
        NSLog(@"dropping re-requested block %@", block.blockHash);
        return; // block was re-requested, drop this one
    }

    NSMutableOrderedSet *txHashes = [NSMutableOrderedSet orderedSetWithArray:block.txHashes];

    [txHashes minusOrderedSet:self.knownTxHashes];

    if (txHashes.count > 0) { // wait til we get all the tx messages before processing the block
        self.currentBlock = block;
        self.currentTxHashes = txHashes;
    }
    else {
        dispatch_async(self.delegateQueue, ^{
            if (_status == BRPeerStatusConnected) [self.delegate peer:self relayedBlock:block];
        });
    }
}

// described in BIP61: https://github.com/bitcoin/bips/blob/master/bip-0061.mediawiki
- (void)acceptRejectMessage:(NSData *)message
{
    NSUInteger off = 0, l = 0;
    NSString *type = [message stringAtOffset:0 length:&off];
    uint8_t code = [message UInt8AtOffset:off++];
    NSString *reason = [message stringAtOffset:off length:&l];
    NSData *txHash = ([MSG_TX isEqual:type]) ? [message hashAtOffset:off + l] : nil;

    NSLog(@"%@:%u rejected %@ code: 0x%x reason: \"%@\"%@%@", self.host, self.port, type, code, reason,
          txHash ? @" txid: " : @"", txHash ? txHash : @"");

    if (txHash.length == CC_SHA256_DIGEST_LENGTH) { // most likely a double spend due to tx missing from wallet
        dispatch_async(self.delegateQueue, ^{
            if (_status == BRPeerStatusConnected) [self.delegate peer:self rejectedTransaction:txHash withCode:code];
        });
    }
}

#pragma mark - hash

#define FNV32_PRIME  0x01000193u
#define FNV32_OFFSET 0x811C9dc5u

// FNV32-1a hash of the ip address and port number: http://www.isthe.com/chongo/tech/comp/fnv/index.html#FNV-1a
- (NSUInteger)hash
{
    uint32_t hash = FNV32_OFFSET;
    
    hash = (hash ^ ((self.address >> 24) & 0xff))*FNV32_PRIME;
    hash = (hash ^ ((self.address >> 16) & 0xff))*FNV32_PRIME;
    hash = (hash ^ ((self.address >> 8) & 0xff))*FNV32_PRIME;
    hash = (hash ^ (self.address & 0xff))*FNV32_PRIME;
    hash = (hash ^ ((self.port >> 8) & 0xff))*FNV32_PRIME;
    hash = (hash ^ (self.port & 0xff))*FNV32_PRIME;
    
    return hash;
}

// two peer objects are equal if they share an ip address and port number
- (BOOL)isEqual:(id)object
{
    return self == object || ([object isKindOfClass:[BRPeer class]] && self.address == [(BRPeer *)object address] &&
                              self.port == [(BRPeer *)object port]);
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"%@:%d %@ stream connected in %fs", self.host, self.port,
                  aStream == self.inputStream ? @"input" : aStream == self.outputStream ? @"output" : @"unkown",
                  [NSDate timeIntervalSinceReferenceDate] - self.startTime);

            if (aStream == self.outputStream) {
                self.startTime = [NSDate timeIntervalSinceReferenceDate]; // don't count connect time in ping time
                [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel pending socket connect timeout
                [self performSelector:@selector(disconnectWithError:)
                 withObject:[NSError errorWithDomain:@"BreadWallet" code:BITCOIN_TIMEOUT_CODE
                             userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"connect timeout", nil)}]
                             afterDelay:CONNECT_TIMEOUT];
            }

            // fall through to send any queued output
        case NSStreamEventHasSpaceAvailable:
            if (aStream != self.outputStream) return;
        
            while (self.outputBuffer.length > 0 && [self.outputStream hasSpaceAvailable]) {
                NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];
                
                if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
                //if(self.outputBuffer.length == 0) NSLog(@"%@:%d output buffer cleared", self.host, self.port);
            }

            break;
            
        case NSStreamEventHasBytesAvailable:
            if (aStream != self.inputStream) return;

            while ([self.inputStream hasBytesAvailable]) {
                NSData *message = nil;
                NSString *type = nil;
                NSInteger headerLen = self.msgHeader.length, payloadLen = self.msgPayload.length, l = 0;
                uint32_t length = 0, checksum = 0;

                if (headerLen < HEADER_LENGTH) { // read message header
                    self.msgHeader.length = HEADER_LENGTH;
                    l = [self.inputStream read:(uint8_t *)self.msgHeader.mutableBytes + headerLen
                         maxLength:self.msgHeader.length - headerLen];
                            
                    if (l < 0) {
                        NSLog(@"%@:%u error reading message", self.host, self.port);
                        goto reset;
                    }
                    
                    self.msgHeader.length = headerLen + l;
                    
                    // consume one byte at a time, up to the magic number that starts a new message header
                    while (self.msgHeader.length >= sizeof(uint32_t) &&
                           [self.msgHeader UInt32AtOffset:0] != BITCOIN_MAGIC_NUMBER) {
#if DEBUG
                        printf("%c", *(const char *)self.msgHeader.bytes);
#endif
                        [self.msgHeader replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
                    }
                    
                    if (self.msgHeader.length < HEADER_LENGTH) continue; // wait for more stream input
                }
                
                if ([self.msgHeader UInt8AtOffset:15] != 0) { // verify msg type field is null terminated
                    [self error:@"malformed message header: %@", self.msgHeader];
                    goto reset;
                }
                
                type = [NSString stringWithUTF8String:(const char *)self.msgHeader.bytes + 4];
                length = [self.msgHeader UInt32AtOffset:16];
                checksum = [self.msgHeader UInt32AtOffset:20];
                        
                if (length > MAX_MSG_LENGTH) { // check message length
                    [self error:@"error reading %@, message length %u is too long", type, length];
                    goto reset;
                }
                
                if (payloadLen < length) { // read message payload
                    self.msgPayload.length = length;
                    l = [self.inputStream read:(uint8_t *)self.msgPayload.mutableBytes + payloadLen
                         maxLength:self.msgPayload.length - payloadLen];
                    
                    if (l < 0) {
                        NSLog(@"%@:%u error reading %@", self.host, self.port, type);
                        goto reset;
                    }
                    
                    self.msgPayload.length = payloadLen + l;
                    if (self.msgPayload.length < length) continue; // wait for more stream input
                }
                
                if (*(const uint32_t *)self.msgPayload.SHA256_2.bytes != checksum) { // verify checksum
                    [self error:@"error reading %@, invalid checksum %x, expected %x, payload length:%u, expected "
                     "length:%u, SHA256_2:%@", type, *(const uint32_t *)self.msgPayload.SHA256_2.bytes, checksum,
                     (int)self.msgPayload.length, length, self.msgPayload.SHA256_2];
                     goto reset;
                }

                message = self.msgPayload;
                self.msgPayload = [NSMutableData data];
                [self acceptMessage:message type:type]; // process message
                
reset:          // reset for next message
                self.msgHeader.length = self.msgPayload.length = 0;
            }

            break;
            
        case NSStreamEventErrorOccurred:
            NSLog(@"%@:%u error connecting, %@", self.host, self.port, aStream.streamError);
            [self disconnectWithError:aStream.streamError];
            break;
            
        case NSStreamEventEndEncountered:
            NSLog(@"%@:%u connection closed", self.host, self.port);
            [self disconnectWithError:nil];
            break;
            
        default:
            NSLog(@"%@:%u unknown network stream eventCode:%u", self.host, self.port, (int)eventCode);
    }
}

@end

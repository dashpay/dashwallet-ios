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
#import "ZNPeerEntity.h"
#import "ZNTransaction.h"
#import "ZNTransactionEntity.h"
#import "ZNMerkleBlock.h"
#import "ZNMerkleBlockEntity.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "NSData+Hash.h"
#import "NSManagedObject+Utils.h"
#import <arpa/inet.h>
#import <netinet/in.h>
#import "Reachability.h"

#define USERAGENT [NSString stringWithFormat:@"/zincwallet:%@/", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]]

#define HEADER_LENGTH          24
#define MAX_MSG_LENGTH         0x02000000
#define ENABLED_SERVICES       0 // we don't provide full blocks to remote nodes
#define PROTOCOL_VERSION       70001
#define MIN_PROTO_VERSION      31402 // peers earlier than this protocol version not supported
#define LOCAL_HOST             0x7f000001
#define REFERENCE_BLOCK_HEIGHT 250000

#define llurand() (((long long unsigned)mrand48() << (sizeof(unsigned)*8)) | (unsigned)mrand48())

typedef enum {
    error = 0,
    tx,
    block,
    merkleblock
} inv_t;

@interface ZNPeer ()

@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableData *msgHeader, *msgPayload, *outputBuffer;
@property (nonatomic, assign) BOOL sentVerack, gotVerack;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) id reachabilityObserver;
@property (nonatomic, assign) uint64_t localNonce;
@property (nonatomic, assign) NSTimeInterval startTime;

@end

@implementation ZNPeer

@dynamic host;

+ (instancetype)peerWithAddress:(uint32_t)address andPort:(uint16_t)port
{
    return [[self alloc] initWithAddress:address andPort:port];
}

- (instancetype)initWithAddress:(uint32_t)address andPort:(uint16_t)port
{
    if (! (self = [self init])) return nil;
    
    _address = address;
    _port = port;
    _pingTime = DBL_MAX;
    
    self.msgHeader = [NSMutableData data];
    self.msgPayload = [NSMutableData data];
    self.outputBuffer = [NSMutableData data];
    self.reachability = [Reachability reachabilityWithHostName:self.host];

    return self;
}

- (void)dealloc
{
    [self.reachability stopNotifier];
    if (self.reachabilityObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
}

- (void)connect
{
    if (self.reachability.currentReachabilityStatus == NotReachable) {
        if (self.reachabilityObserver) return;
        
        self.reachabilityObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification
            object:self.reachability queue:nil usingBlock:^(NSNotification *note) {
                if (self.reachability.currentReachabilityStatus == NotReachable) return;

                [self connect];
            }];
        [self.reachability startNotifier];
    }
    else if (self.reachabilityObserver) {
        [self.reachability stopNotifier];
        [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
        self.reachabilityObserver = nil;
    }

    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    
    NSLog(@"%@:%u connecting", self.host, self.port);
    _status = connecting;

    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.host, self.port, &readStream, &writeStream);
    self.inputStream = CFBridgingRelease(readStream);
    self.outputStream = CFBridgingRelease(writeStream);
    self.inputStream.delegate = self.outputStream.delegate = self;
    
    // we may want to use a different thread for each peer
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    // after the reachablity check, the radios should be warmed up and we can set a short socket connect timeout
    [self performSelector:@selector(disconnectWithError:) withObject:[NSError errorWithDomain:@"ZincWallet" code:1001
     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%@:%u socket connect timeout", self.host,
                                           self.port]}] afterDelay:2];
    
    [self.inputStream open];
    [self.outputStream open];
    
    [self sendVersionMessage];
}

- (void)disconnectWithError:(NSError *)error
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel connect timeout
    
    [self.inputStream close];
    [self.outputStream close];

    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    self.gotVerack = self.sentVerack = NO;
    _status = disconnected;
    [self.delegate peer:self disconnectedWithError:error];
}

- (NSString *)host
{
    struct in_addr addr = { CFSwapInt32HostToBig(self.address) };
    char s[INET_ADDRSTRLEN];

    return [NSString stringWithUTF8String:inet_ntop(AF_INET, &addr, s, INET_ADDRSTRLEN)];
}

// change state to connected if appropriate
- (void)didConnect
{
    if (self.status != connecting || ! self.sentVerack || ! self.gotVerack) return;

    NSLog(@"%@:%d handshake completed", self.host, self.port);
    
    _status = connected;
    [self.delegate peerConnected:self];
}

#pragma mark - send

- (void)sendMessage:(NSData *)message type:(NSString *)type
{
    NSLog(@"%@:%d sending %@", self.host, self.port, type);

    [self.outputBuffer appendMessage:message type:type];
    
    while (self.outputBuffer.length > 0 && [self.outputStream hasSpaceAvailable]) {
        NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];

        if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
        
        if (self.outputBuffer.length == 0) NSLog(@"%@:%d output buffer cleared", self.host, self.port);
    }
}

- (void)sendVersionMessage
{
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendUInt32:PROTOCOL_VERSION]; // version
    [msg appendUInt64:ENABLED_SERVICES]; // services
    [msg appendUInt64:[NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970]; // timestamp
    [msg appendNetAddress:self.address port:self.port services:self.services]; // address of remote peer
    [msg appendNetAddress:LOCAL_HOST port:STANDARD_PORT services:ENABLED_SERVICES]; // address of local peer
    [msg appendUInt64:(self.localNonce = llurand())]; // random nonce
    [msg appendString:USERAGENT]; // user agent
    //TODO: XXXX get last block stored in core data
    [msg appendUInt32:REFERENCE_BLOCK_HEIGHT]; // last block received
    [msg appendUInt8:0]; // relay transactions (no for SPV bloom filter mode)
    
    [self performSelector:@selector(disconnectWithError:) withObject:[NSError errorWithDomain:@"ZincWallet" code:1001
     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%@:%u verack timeout", self.host, self.port]}]
     afterDelay:5];

    self.startTime = [NSDate timeIntervalSinceReferenceDate];
    [self sendMessage:msg type:MSG_VERSION];
}

- (void)sendVerackMessage
{
    [self sendMessage:[NSData data] type:MSG_VERACK];
    self.sentVerack = YES;
    [self didConnect];
}

- (void)sendAddrMessage
{
    NSMutableData *msg = [NSMutableData data];
    
    //TODO: send addresses we know about
    [msg appendVarInt:0];
    [self sendMessage:msg type:MSG_ADDR];
}

- (void)sendGetdataMessageWithTxHashes:(NSArray *)txHashes andBlockHashes:(NSArray *)blockHashes
{
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

    [self sendMessage:msg type:MSG_GETDATA];
}

// peer will send an inv message in response to getblocks
- (void)sendGetblocksMessage
{
    NSMutableData *msg = [NSMutableData data];
    NSFetchRequest *req = [ZNMerkleBlockEntity fetchRequest];
    uint32_t step = 1, start = 0;
    uint32_t top = [[ZNMerkleBlockEntity objectsSortedBy:@"height" ascending:NO offset:0 limit:1].lastObject height];
    NSMutableArray *heights = [NSMutableArray array];

    [msg appendUInt32:PROTOCOL_VERSION];
    
    // append the 10 most recent block hashes decending, then continue appending while doubling the step back each time,
    // finishing with the genisis block (top, -1, -2, -3, -4, -5, -6, -7, -8, -9, -11, -13, -17, -25, -41, -73, ..., 0)
    for (uint32_t i = top; i > 0; i -= step, ++start) {
        if (start >= 10) step *= 2;

        [heights addObject:@(i)];
    }
    
    [heights addObject:@(0)];
    
    [msg appendVarInt:heights.count]; // number of block locator hashes
    
    req.predicate = [NSPredicate predicateWithFormat:@"height IN %@", heights];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"height" ascending:NO]];

    //XXX handle no blocks case, and use performBlockAndWait
    for (ZNMerkleBlockEntity *e in [ZNMerkleBlockEntity fetchObjects:req]) {
        [msg appendData:e.blockHash];
    }

    [msg appendBytes:"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" length:32]; // hash stop
    
    [self sendMessage:msg type:MSG_GETBLOCKS];
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

#pragma mark - accept

- (void)acceptMessage:(NSData *)message type:(NSString *)type
{
    // update timestamp for peer
    [ZNPeerEntity createOrUpdateWithAddress:self.address port:self.port
     timestamp:[NSDate timeIntervalSinceReferenceDate] services:self.services];

    if ([MSG_VERSION isEqual:type]) [self acceptVersionMessage:message];
    else if ([MSG_VERACK isEqual:type]) [self acceptVerackMessage:message];
    else if ([MSG_ADDR isEqual:type]) [self acceptAddrMessage:message];
    else if ([MSG_INV isEqual:type]) [self acceptInvMessage:message];
    //else if ([MSG_GETDATA isEqual:type]) [self acceptGetdataMessage:message];
    //else if ([MSG_NOTFOUND isEqual:type]) [self acceptNotfoundMessage:message];
    //else if ([MSG_GETBLOCKS isEqual:type]) [self acceptGetblocksMessage:message];
    //else if ([MSG_GETHEADERS isEqual:type]) [self acceptGetheadersMessage:message];
    else if ([MSG_TX isEqual:type]) [self acceptTxMessage:message];
    //else if ([MSG_BLOCK isEqual:type]) [self acceptBlockMessage:message];
    //else if ([MSG_HEADERS isEqual:type]) [self acceptHeadersMessage:message];
    else if ([MSG_GETADDR isEqual:type]) [self acceptGetaddrMessage:message];
    //else if ([MSG_MEMPOOL isEqual:type]) [self acceptMempoolMessage:message];
    //else if ([MSG_CHECKORDER isEqual:type]) [self acceptCheckorderMessage:message];
    //else if ([MSG_SUBMITORDER isEqual:type]) [self acceptSubmitorderMessage:message];
    //else if ([MSG_REPLY isEqual:type]) [self acceptReplyMessage:message];
    else if ([MSG_PING isEqual:type]) [self acceptPingMessage:message];
    else if ([MSG_PONG isEqual:type]) [self acceptPongMessage:message];
    //else if ([MSG_FILTERLOAD isEqual:type]) [self acceptFilterloadMessage:message];
    //else if ([MSG_FILTERADD isEqual:type]) [self acceptFilteraddMessage:message];
    //else if ([MSG_FILTERCLEAR isEqual:type]) [self acceptFilterclearMessage:message];
    else if ([MSG_MERKLEBLOCK isEqual:type]) [self acceptMerkleblockMessage:message];
    //else if ([MSG_ALERT isEqual:type]) [self acceptAlertMessage:message];

    else NSLog(@"%@:%d dropping %@ length %u, not implemented", self.host, self.port, type, (int)message.length);
}

- (void)acceptVersionMessage:(NSData *)message
{
    NSUInteger l = 0;
    
    if (message.length < 85) {
        NSLog(@"%@:%d malformed version message, length is %u, should be > 84", self.host, self.port,
              (int)message.length);
        return;
    }
    
    _version = [message UInt32AtOffset:0];
    
    if (self.version < MIN_PROTO_VERSION) {
        [self disconnectWithError:[NSError errorWithDomain:@"ZincWallet" code:500
         userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%@:%u protocol version %u not supported",
                                               self.host, self.port, self.version]}]];
        return;
    }
    
    _services = [message UInt64AtOffset:4];
    _timestamp = [message UInt64AtOffset:12];
    _useragent = [message stringAtOffset:80 length:&l];

    if (message.length != 80 + l + sizeof(uint32_t)) {
        NSLog(@"%@:%d malformed version message, length is %u, should be %lu", self.host, self.port,
              (int)message.length, 80 + l + sizeof(uint32_t));
        return;
    }
    
    _lastblock = [message UInt32AtOffset:80 + l];
    
    NSLog(@"%@:%d got version, useragent:\"%@\"", self.host, self.port, self.useragent);
    
    [self sendVerackMessage];
}

- (void)acceptVerackMessage:(NSData *)message
{
    if (message.length != 0) {
        NSLog(@"%@:%d malformed verack message %@", self.host, self.port, message);
        return;
    }
    else if (self.gotVerack) {
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
        NSLog(@"%@:%d malformed addr message, length %u is too short", self.host, self.port, (int)message.length);
        return;
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSFetchRequest *req = [ZNPeerEntity fetchRequest];
    NSUInteger l, count = [message varIntAtOffset:0 length:&l];
    NSMutableArray *addresses = [NSMutableArray array], *ports = [NSMutableArray array],
                   *timestamps = [NSMutableArray array], *services = [NSMutableArray array];
    
    if (count > 1000) {
        NSLog(@"%@:%d dropping addr message, %u is too many addresses (max 1000)", self.host, self.port, (int)count);
        return;
    }
    else if (message.length != l + 30*count) {
        NSLog(@"%@:%d malformed addr message, length is %u, should be %u for %u addresses", self.host, self.port,
              (int)message.length, (int)(l + 30*count), (int)count);
        return;
    }
    else NSLog(@"%@:%d got addr with %u addresses", self.host, self.port, (int)count);
    
    for (uint64_t i = 0; i < count; i++) {
        NSTimeInterval timestamp = [message UInt32AtOffset:l + 30*i] - NSTimeIntervalSince1970;

        [services addObject:@([message UInt64AtOffset:l + 30*i + 4])];
        [addresses addObject:@(CFSwapInt32BigToHost(*(uint32_t *)((uint8_t *)message.bytes + l + 30*i + 24)))];
        [ports addObject:@(CFSwapInt16BigToHost(*(uint16_t *)((uint8_t *)message.bytes + l + 30*i + 28)))];
            
        // if address time is more than 10min in the future or before reference date, set to 5 days old
        if (timestamp > now + 10*60 || timestamp < 0) timestamp = now - 5*24*60*60;
        [timestamps addObject:@(timestamp - 2*60*60)]; // subtract two hours and add it to the list
    }
    
    [ZNPeerEntity createOrUpdateWithAddresses:addresses ports:ports timestamps:timestamps services:services];
    
    count = [ZNPeerEntity countAllObjects];
    
    if (count > 1000) { // remove peers with a timestamp more than 3 hours old, or until there are only 1000 left
        req.predicate = [NSPredicate predicateWithFormat:@"timestamp < %@",
                         [NSDate dateWithTimeIntervalSinceReferenceDate:now - 3*60*60]];
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:YES]];
        req.fetchLimit = count - 1000;
        [ZNPeerEntity deleteObjects:[ZNPeerEntity fetchObjects:req]];
        
        // limit total to 2500 peers
        [ZNPeerEntity deleteObjects:[ZNPeerEntity objectsSortedBy:@"timestamp" ascending:NO offset:2500 limit:0]];
    }
}

- (void)acceptInvMessage:(NSData *)message
{
    NSUInteger l, count = [message varIntAtOffset:0 length:&l];
    NSMutableArray *txHashes = [NSMutableArray array], *blockHashes = [NSMutableArray array];
    
    if (l == 0 || message.length < l + count*36) {
        NSLog(@"%@:%u malformed inv message, length is %u, should be %u for %u items", self.host, self.port,
              (int)message.length, (int)(l == 0 ? 1 : l) + (int)count*36, (int)count);
        return;
    }
    else if (count > 50000) {
        NSLog(@"%@:%u dropping inv message, %u is too many items (max 50000)", self.host, self.port, (int)count);
        return;
    }
    
    for (NSUInteger i = 0; i < count; i++) {
        inv_t type = [message UInt32AtOffset:l + i*36];
        NSData *hash = [message hashAtOffset:l + i*36 + sizeof(uint32_t)];
        
        if (! hash) continue;
        
        switch (type) {
            case tx: [txHashes addObject:hash]; break;
            case block: [blockHashes addObject:hash]; break;
            case merkleblock: [blockHashes addObject:hash]; break;
            default: break;
        }
    }

    NSLog(@"%@:%u got inv with %u items", self.host, self.port, (int)count);
    
    // remove transactions we already know about
    [txHashes removeObjectsInArray:[[ZNTransactionEntity objectsMatching:@"txHash IN %@", txHashes]
                                    valueForKey:@"txHash"]];
    [blockHashes removeObjectsInArray:[[ZNMerkleBlockEntity objectsMatching:@"blockHash IN %@", blockHashes]
                                       valueForKey:@"blockHash"]];
    
    if (txHashes.count + blockHashes.count > 0) {
        [self sendGetdataMessageWithTxHashes:txHashes andBlockHashes:blockHashes];
    }
}

- (void)acceptTxMessage:(NSData *)message
{
    ZNTransaction *tx = [[ZNTransaction alloc] initWithData:message];
    
    if (! tx) {
        NSLog(@"%@:%d malformed tx message %@", self.host, self.port, message);
        return;
    }
    
    [self.delegate peer:self relayedTransaction:tx];
}

- (void)acceptGetaddrMessage:(NSData *)message
{
    if (message.length != 0) {
        NSLog(@"%@:%d malformed getaddr message %@", self.host, self.port, message);
        return;
    }

    NSLog(@"%@:%u got getaddr", self.host, self.port);
    
    [self sendAddrMessage];
}

- (void)acceptPingMessage:(NSData *)message
{
    if (message.length != sizeof(uint64_t)) {
        NSLog(@"%@:%d malformed ping message, length is %u, should be 4", self.host, self.port, (int)message.length);
        return;
    }
    
    NSLog(@"%@:%u got ping", self.host, self.port);
    
    [self sendMessage:message type:MSG_PONG];
}

- (void)acceptPongMessage:(NSData *)message
{
    if (message.length != sizeof(uint64_t)) {
        NSLog(@"%@:%d malformed pong message, length is %u, should be 4", self.host, self.port, (int)message.length);
        return;
    }
    else if ([message UInt64AtOffset:0] != self.localNonce) {
        NSLog(@"%@:%d pong message contained wrong nonce: %llu, expected: %llu", self.host, self.port,
              [message UInt64AtOffset:0], self.localNonce);
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
    // non-tx message is received we should have all the tx in the merkleblock. If not, the only way to request them is
    // re-request the merkleblock. The simplest way to do this is to delete the block and let the block organization
    // algorithm figure it out what needs to be requested.
    
    [ZNMerkleBlockEntity createOrUpdateWithMerkleBlock:[ZNMerkleBlock blockWithMessage:message]];

    NSLog(@"%@:%u got merkleblock", self.host, self.port);
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
    hash = (hash ^ ((self.address >> 0) & 0xff))*FNV32_PRIME;
    hash = (hash ^ ((self.port >> 8) & 0xff))*FNV32_PRIME;
    hash = (hash ^ ((self.port >> 0) & 0xff))*FNV32_PRIME;
    
    return hash;
}

// two peer objects are equal if they share an ip address and port number
- (BOOL)isEqual:(id)object
{
    return ([object isKindOfClass:[ZNPeer class]] && self.address == ((ZNPeer *)object).address &&
            self.port == ((ZNPeer *)object).port) ? YES : NO;
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"%@:%d %@ stream connected in %fs", self.host, self.port,
                  aStream == self.inputStream ? @"input" : aStream == self.outputStream ? @"output" : @"unkown",
                  [NSDate timeIntervalSinceReferenceDate] - self.startTime);
            [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel pending connect timeout

            // don't count socket connect time in ping time
            if (aStream == self.outputStream) self.startTime = [NSDate timeIntervalSinceReferenceDate];

            // fall through to send any queued output
        case NSStreamEventHasSpaceAvailable:
            if (aStream != self.outputStream) break;
            
            while (self.outputBuffer.length > 0 && [self.outputStream hasSpaceAvailable]) {
                NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];
                
                if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];

                if (self.outputBuffer.length == 0) NSLog(@"%@:%d output buffer cleared", self.host, self.port);
            }
            
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (aStream != self.inputStream) return;

            while ([self.inputStream hasBytesAvailable]) {
                NSString *type = nil;
                uint32_t length = 0, checksum = 0;
                NSInteger headerLen = self.msgHeader.length, payloadLen = self.msgPayload.length, l = 0;
                        
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
                           [self.msgHeader UInt32AtOffset:0] != MAGIC_NUMBER) {
#if DEBUG
                        printf("%c", *(char *)self.msgHeader.bytes);
#endif
                        [self.msgHeader replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
                    }
                    
                    if (self.msgHeader.length < HEADER_LENGTH) continue; // wait for more stream input
                }
                
                if ([self.msgHeader UInt8AtOffset:15] != 0) { // verify msg type field is null terminated
                    NSLog(@"%@:%u malformed message header %@", self.host, self.port, self.msgHeader);
                    goto reset;
                }
                
                type = [NSString stringWithUTF8String:(char *)self.msgHeader.bytes + 4];
                length = [self.msgHeader UInt32AtOffset:16];
                checksum = [self.msgHeader UInt32AtOffset:20];
                        
                if (length > MAX_MSG_LENGTH) { // check message length
                    NSLog(@"%@:%u error reading %@, message length %u is too long", self.host, self.port, type, length);
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
                
                if (*(uint32_t *)[self.msgPayload SHA256_2].bytes != checksum) { // verify checksum
                    NSLog(@"%@:%u error reading %@, invalid checksum %x, expected %x, payload length:%u, expected "
                          "length:%u, SHA256_2:%@", self.host, self.port, type,
                          *(uint32_t *)[self.msgPayload SHA256_2].bytes, checksum, (int)self.msgPayload.length, length,
                          [self.msgPayload SHA256_2]);
                }
                else {
                    NSData *message = self.msgPayload;
                    
                    self.msgPayload = [NSMutableData data];
                    
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        [self acceptMessage:message type:type]; // process message
                    });
                }
                
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

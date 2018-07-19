//
//  DSPeer.h
//  DashSync
//
//  Created by Aaron Voisine on 10/9/13.
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
#import "DSChain.h"
#import "IntTypes.h"



#define BITCOIN_TIMEOUT_CODE  1001

#define SERVICES_NODE_NETWORK 0x01 // services value indicating a node carries full blocks, not just headers
#define SERVICES_NODE_BLOOM   0x04 // BIP111: https://github.com/bitcoin/bips/blob/master/bip-0111.mediawiki
#define USER_AGENT            [NSString stringWithFormat:@"/dashwallet:%@/",\
                               NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]]

#define WEEK_TIME_INTERVAL 604800 //7*24*60*60
#define DAY_TIME_INTERVAL 86400 //24*60*60
#define HOUR_TIME_INTERVAL 3600

// explanation of message types at: https://en.bitcoin.it/wiki/Protocol_specification
#define MSG_VERSION     @"version"
#define MSG_VERACK      @"verack"
#define MSG_ADDR        @"addr"
#define MSG_INV         @"inv"
#define MSG_GETDATA     @"getdata"
#define MSG_NOTFOUND    @"notfound"
#define MSG_GETBLOCKS   @"getblocks"
#define MSG_GETHEADERS  @"getheaders"
#define MSG_TX          @"tx"
#define MSG_IX          @"ix"
#define MSG_BLOCK       @"block"
#define MSG_HEADERS     @"headers"
#define MSG_GETADDR     @"getaddr"
#define MSG_MEMPOOL     @"mempool"
#define MSG_PING        @"ping"
#define MSG_PONG        @"pong"
#define MSG_FILTERLOAD  @"filterload"
#define MSG_FILTERADD   @"filteradd"
#define MSG_FILTERCLEAR @"filterclear"
#define MSG_MERKLEBLOCK @"merkleblock"
#define MSG_ALERT       @"alert"
#define MSG_REJECT      @"reject"      // BIP61: https://github.com/bitcoin/bips/blob/master/bip-0061.mediawiki
#define MSG_SENDHEADERS @"sendheaders" // BIP130: https://github.com/bitcoin/bips/blob/master/bip-0130.mediawiki
#define MSG_FEEFILTER   @"feefilter"   // BIP133: https://github.com/bitcoin/bips/blob/master/bip-0133.mediawiki

//Dash specific

//Control

#define MSG_SPORK      @"spork"
#define MSG_GETSPORKS  @"getsporks"

//Masternode

#define MSG_DSEG          @"dseg"
#define MSG_MNB           @"mnb"
#define MSG_MNGET         @"mnget"
#define MSG_MNP           @"mnp"
#define MSG_MNV           @"mnv"
#define MSG_MNW           @"mnw"
#define MSG_MNWB          @"mnwb"
#define MSG_SSC           @"ssc"
#define MSG_GETMNLISTDIFF @"getmnlistd"
#define MSG_MNLISTDIFF    @"mnlistdiff"

//Governance

#define MSG_GOVOBJ      @"govobj"
#define MSG_GOVOBJVOTE  @"govobjvote"
#define MSG_GOVOBJSYNC  @"govsync"

//Private send

#define MSG_DARKSENDANNOUNCE       @"dsa"
#define MSG_DARKSENDCONTROL        @"dsc"
#define MSG_DARKSENDFINISH         @"dsf"
#define MSG_DARKSENDINITIATE       @"dsi"
#define MSG_DARKSENDQUORUM         @"dsq"
#define MSG_DARKSENDSESSION        @"dss"
#define MSG_DARKSENDSESSIONUPDATE  @"dssu"
#define MSG_DARKSENDTX             @"dstx"

#define REJECT_INVALID     0x10 // transaction is invalid for some reason (invalid signature, output value > input, etc)
#define REJECT_SPENT       0x12 // an input is already spent
#define REJECT_NONSTANDARD 0x40 // not mined/relayed because it is "non-standard" (type or version unknown by server)
#define REJECT_DUST        0x41 // one or more output amounts are below the 'dust' threshold
#define REJECT_LOWFEE      0x42 // transaction does not have enough fee/priority to be relayed or mined

typedef union _UInt256 UInt256;
typedef union _UInt128 UInt128;

typedef NS_ENUM(uint32_t, DSGovernanceRequestState) {
    DSGovernanceRequestState_None,
    DSGovernanceRequestState_GovernanceObjectHashes,
    DSGovernanceRequestState_GovernanceObjectHashesCountReceived,
    DSGovernanceRequestState_GovernanceObjectHashesReceived,
    DSGovernanceRequestState_GovernanceObjects,
    DSGovernanceRequestState_GovernanceObjectVoteHashes,
    DSGovernanceRequestState_GovernanceObjectVoteHashesCountReceived,
    DSGovernanceRequestState_GovernanceObjectVoteHashesReceived,
    DSGovernanceRequestState_GovernanceObjectVotes,
};


typedef NS_ENUM(uint32_t, DSSyncCountInfo);

@class DSPeer, DSTransaction, DSMerkleBlock, DSChain,DSSpork,DSMasternodeBroadcast,DSMasternodePing,DSGovernanceObject,DSGovernanceVote;

@protocol DSPeerDelegate<NSObject>
@required

- (void)peerConnected:(DSPeer *)peer;
- (void)peer:(DSPeer *)peer disconnectedWithError:(NSError *)error;
- (void)peer:(DSPeer *)peer relayedPeers:(NSArray *)peers;
- (void)peer:(DSPeer *)peer relayedTransaction:(DSTransaction *)transaction;
- (void)peer:(DSPeer *)peer hasTransaction:(UInt256)txHash;
- (void)peer:(DSPeer *)peer rejectedTransaction:(UInt256)txHash withCode:(uint8_t)code;

// called when the peer relays either a merkleblock or a block header, headers will have 0 totalTransactions
- (void)peer:(DSPeer *)peer relayedBlock:(DSMerkleBlock *)block;

- (void)peer:(DSPeer *)peer notfoundTxHashes:(NSArray *)txHashes andBlockHashes:(NSArray *)blockhashes;
- (void)peer:(DSPeer *)peer setFeePerKb:(uint64_t)feePerKb;
- (DSTransaction *)peer:(DSPeer *)peer requestedTransaction:(UInt256)txHash;

- (void)peer:(DSPeer *)peer relayedSpork:(DSSpork *)spork;

- (void)peer:(DSPeer *)peer relayedSyncInfo:(DSSyncCountInfo)syncCountInfo count:(uint32_t)count;
- (void)peer:(DSPeer *)peer relayedMasternodeBroadcast:(DSMasternodeBroadcast*)masternodeBroadcast;
- (void)peer:(DSPeer *)peer relayedMasternodePing:(DSMasternodePing*)masternodePing;

- (void)peer:(DSPeer *)peer relayedGovernanceObject:(DSGovernanceObject *)governanceObject;
- (void)peer:(DSPeer *)peer relayedGovernanceVote:(DSGovernanceVote *)governanceVote;

- (void)peer:(DSPeer *)peer hasMasternodeBroadcastHashes:(NSSet*)masternodeBroadcastHashes;
- (void)peer:(DSPeer *)peer relayedMasternodeDiffMessage:(NSData*)masternodeDiffMessage;

- (void)peer:(DSPeer *)peer hasGovernanceObjectHashes:(NSSet*)governanceObjectHashes;
- (void)peer:(DSPeer *)peer hasGovernanceVoteHashes:(NSSet*)governanceVoteHashes;

- (void)peer:(DSPeer *)peer hasSporkHashes:(NSSet*)sporkHashes;

- (void)peer:(DSPeer *)peer ignoredGovernanceSync:(DSGovernanceRequestState)governanceRequestState;

@end

typedef NS_ENUM(NSUInteger, DSPeerStatus) {
    DSPeerStatus_Disconnected = 0,
    DSPeerStatus_Connecting,
    DSPeerStatus_Connected
};

typedef NS_ENUM(NSUInteger, DSPeerType) {
    DSPeerType_FullNode = 0,
    DSPeerType_MasterNode
};

@interface DSPeer : NSObject<NSStreamDelegate>

@property (nonatomic, readonly) id<DSPeerDelegate> delegate;
@property (nonatomic, readonly) dispatch_queue_t delegateQueue;

// set this to the timestamp when the wallet was created to improve initial sync time (interval since reference date)
@property (nonatomic, assign) NSTimeInterval earliestKeyTime;

@property (nonatomic, readonly) DSPeerStatus status;
@property (nonatomic, readonly) DSPeerType type;
@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) UInt128 address;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) uint64_t services;
@property (nonatomic, readonly) uint32_t version;
@property (nonatomic, readonly) uint64_t nonce;
@property (nonatomic, readonly) NSString *useragent;
@property (nonatomic, readonly) uint32_t lastblock;
@property (nonatomic, readonly) uint64_t feePerKb; // minimum tx fee rate peer will accept
@property (nonatomic, readonly) NSTimeInterval pingTime;
@property (nonatomic, readonly) NSTimeInterval relaySpeed; // headers or block->totalTx per second being relayed
@property (nonatomic, assign) NSTimeInterval timestamp; // timestamp reported by peer (interval since refrence date)
@property (nonatomic, assign) int16_t misbehavin;
@property (nonatomic, assign) uint32_t priority;
@property (nonatomic, assign) NSTimeInterval lowPreferenceTill;
@property (nonatomic, assign) NSTimeInterval lastRequestedMasternodeList;
@property (nonatomic, assign) NSTimeInterval lastRequestedGovernanceSync;
@property (nonatomic, assign) DSGovernanceRequestState governanceRequestState;

@property (nonatomic, assign) BOOL needsFilterUpdate; // set this when wallet addresses need to be added to bloom filter
@property (nonatomic, assign) uint32_t currentBlockHeight; // set this to local block height (helps detect tarpit nodes)
@property (nonatomic, assign) BOOL synced; // use this to keep track of peer state

@property (nonatomic, readonly) DSChain * chain;

+ (instancetype)peerWithAddress:(UInt128)address andPort:(uint16_t)port onChain:(DSChain*)chain;
+ (instancetype)peerWithHost:(NSString *)host onChain:(DSChain*)chain;

- (instancetype)initWithAddress:(UInt128)address andPort:(uint16_t)port onChain:(DSChain*)chain;
- (instancetype)initWithAddress:(UInt128)address port:(uint16_t)port onChain:(DSChain*)chain timestamp:(NSTimeInterval)timestamp
services:(uint64_t)services;
- (instancetype)initWithHost:(NSString *)host onChain:(DSChain*)chain;
- (void)setDelegate:(id<DSPeerDelegate>)delegate queue:(dispatch_queue_t)delegateQueue;
- (void)connect;
- (void)disconnect;
- (void)sendMessage:(NSData *)message type:(NSString *)type;
- (void)sendFilterloadMessage:(NSData *)filter;
- (void)sendMempoolMessage:(NSArray *)publishedTxHashes completion:(void (^)(BOOL success))completion;
- (void)sendGetheadersMessageWithLocators:(NSArray *)locators andHashStop:(UInt256)hashStop;
- (void)sendGetblocksMessageWithLocators:(NSArray *)locators andHashStop:(UInt256)hashStop;
- (void)sendInvMessageWithTxHashes:(NSArray *)txHashes;
- (void)sendGetdataMessageWithTxHashes:(NSArray *)txHashes andBlockHashes:(NSArray *)blockHashes;
- (void)sendGetdataMessageWithMasternodeBroadcastHashes:(NSArray<NSData*> *)masternodeBroadcastHashes;
- (void)sendGetdataMessageWithGovernanceObjectHashes:(NSArray<NSData*> *)governanceObjectHashes;
- (void)sendGetdataMessageWithGovernanceVoteHashes:(NSArray<NSData*> *)governanceVoteHashes;
- (void)sendGetMasternodeListFromPreviousBlockHash:(UInt256)previousBlockHash forBlockHash:(UInt256)blockHash;
- (void)sendGetaddrMessage;
- (void)sendGovSync;
- (void)sendGovSync:(UInt256)h;
- (void)sendGovObject:(DSGovernanceObject*)governanceObject;
- (void)sendGovObjectVote:(DSGovernanceVote*)governanceVote;
- (void)sendPingMessageWithPongHandler:(void (^)(BOOL success))pongHandler;
- (void)sendGetSporks;
- (void)sendDSegMessage:(DSUTXO)utxo;
- (void)rerequestBlocksFrom:(UInt256)blockHash; // useful to get additional transactions after a bloom filter update

-(NSString*)chainTip;



@end

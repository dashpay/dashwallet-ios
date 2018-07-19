//
//  DSChainPeerManager.h
//  DashSync
//
//  Created by Aaron Voisine on 10/6/13.
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

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "DSChain.h"
#import "DSPeer.h"

typedef NS_ENUM(uint32_t, DSSyncCountInfo) {
    DSSyncCountInfo_List = 2,
    DSSyncCountInfo_MNW = 3,
    DSSyncCountInfo_GovernanceObject = 10,
    DSSyncCountInfo_GovernanceObjectVote = 11,
};

FOUNDATION_EXPORT NSString* _Nonnull const DSChainPeerManagerSyncStartedNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSChainPeerManagerSyncFinishedNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSChainPeerManagerSyncFailedNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSChainPeerManagerTxStatusNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSChainPeerManagerNewBlockNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSChainPeerManagerNotificationChainKey;

#define PEER_MAX_CONNECTIONS 3
#define SETTINGS_FIXED_PEER_KEY @"SETTINGS_FIXED_PEER"


#define LAST_SYNCED_GOVERANCE_OBJECTS @"LAST_SYNCED_GOVERANCE_OBJECTS"
#define LAST_SYNCED_MASTERNODE_LIST @"LAST_SYNCED_MASTERNODE_LIST"

@class DSTransaction,DSGovernanceSyncManager,DSMasternodeManager,DSSporkManager,DSPeer,DSGovernanceVote;

@interface DSChainPeerManager : NSObject <DSPeerDelegate, DSChainDelegate, UIAlertViewDelegate>

@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) double syncProgress;
@property (nonatomic, readonly) NSUInteger peerCount; // number of connected peers
@property (nonatomic, readonly) NSString * _Nullable downloadPeerName;
@property (nonatomic, readonly) DSChain * chain;
@property (nonatomic, readonly) DSPeer * downloadPeer, *fixedPeer;
@property (nonatomic, readonly) DSSporkManager * sporkManager;
@property (nonatomic, readonly) DSMasternodeManager * masternodeManager;
@property (nonatomic, readonly) DSGovernanceSyncManager * governanceSyncManager;
@property (nonatomic, readonly) NSArray* registeredDevnetPeers;
@property (nonatomic, readonly) NSArray* registeredDevnetPeerServices;

- (instancetype)initWithChain:(DSChain*)chain;

- (void)connect;
- (void)clearPeers;
- (void)disconnect;
- (void)rescan;
- (void)publishTransaction:(DSTransaction * _Nonnull)transaction
                completion:(void (^ _Nonnull)(NSError * _Nullable error))completion;
-(void)publishVotes:(NSArray<DSGovernanceVote*>*)votes;
-(void)publishProposal:(DSGovernanceObject*)goveranceProposal;
- (NSUInteger)relayCountForTransaction:(UInt256)txHash; // number of connected peers that have relayed the transaction

// Masternodes
//-(uint32_t)countForSyncCountInfo:(DSSyncCountInfo)masternodeSyncCountInfo;
-(void)setCount:(uint32_t)count forSyncCountInfo:(DSSyncCountInfo)masternodeSyncCountInfo;

-(void)clearRegisteredPeers;
-(void)registerPeerAtLocation:(UInt128)IPAddress port:(uint32_t)port;

-(void)getSporks;

@end

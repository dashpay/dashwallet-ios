//
//  DSWalletConstants.m
//  DashSync
//
//  Created by Samuel Sutch on 6/3/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>

NSString* const DSChainPeerManagerSyncStartedNotification =      @"DSChainPeerManagerSyncStartedNotification";
NSString* const DSChainPeerManagerSyncFinishedNotification =     @"DSChainPeerManagerSyncFinishedNotification";
NSString* const DSChainPeerManagerSyncFailedNotification =       @"DSChainPeerManagerSyncFailedNotification";
NSString* const DSChainPeerManagerTxStatusNotification =         @"DSChainPeerManagerTxStatusNotification";
NSString* const DSChainPeerManagerNewBlockNotification =         @"DSChainPeerManagerNewBlockNotification";

NSString* const DSChainPeerManagerNotificationChainKey =         @"DSChainPeerManagerNotificationChainKey";

NSString* const DSChainWalletsDidChangeNotification =    @"DSChainWalletsDidChangeNotification";
NSString* const DSChainStandaloneDerivationPathsDidChangeNotification =    @"DSChainStandaloneDerivationPathsDidChangeNotification";
NSString* const DSChainStandaloneAddressesDidChangeNotification = @"DSChainStandaloneAddressesDidChangeNotification";
NSString* const DSWalletBalanceChangedNotification =        @"DSWalletBalanceChangedNotification";

NSString* const DSSporkListDidUpdateNotification =     @"DSSporkListDidUpdateNotification";

NSString* const DSMasternodeListDidChangeNotification = @"DSMasternodeListDidChangeNotification";
NSString* const DSMasternodeListCountUpdateNotification = @"DSMasternodeListCountUpdateNotification";

NSString* const DSGovernanceObjectListDidChangeNotification = @"DSGovernanceObjectListDidChangeNotification";
NSString* const DSGovernanceVotesDidChangeNotification = @"DSGovernanceVotesDidChangeNotification";
NSString* const DSGovernanceObjectCountUpdateNotification = @"DSGovernanceObjectCountUpdateNotification";
NSString* const DSGovernanceVoteCountUpdateNotification = @"DSGovernanceVoteCountUpdateNotification";

NSString* const DSChainsDidChangeNotification = @"DSChainsDidChangeNotification";

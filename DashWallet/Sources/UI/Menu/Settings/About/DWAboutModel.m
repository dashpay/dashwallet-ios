//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DWAboutModel.h"

#import <arpa/inet.h>
#import <netdb.h>
#import <sys/socket.h>

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAboutModel ()

@property id exploreDashDatabaseState;

@end

@implementation DWAboutModel

- (instancetype)init {
    self = [super init];

    if (self) {
        __weak typeof(self) wself = self;
        self.exploreDashDatabaseState = [[NSNotificationCenter defaultCenter]
            addObserverForName:@"databaseHasBeenUpdatedNotification"
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *_Nonnull note) {
                        [wself.delegate exploreDashDatabaseSyncStateChanged];
                    }];
    }

    return self;
}
+ (NSURL *)supportURL {
    NSURL *url = [NSURL URLWithString:@"https://support.dash.org/en/support/solutions"];
    return url;
}

- (NSString *)appVersion {
    DWEnvironment *environment = [DWEnvironment sharedInstance];
    NSString *networkString = @"";
    if (![environment.currentChain isMainnet]) {
        networkString = [NSString stringWithFormat:@" (%@)", environment.currentChain.name];
    }

    NSBundle *bundle = [NSBundle mainBundle];

    return [NSString stringWithFormat:@"DashWallet v%@ - %@%@",
                                      bundle.infoDictionary[@"CFBundleShortVersionString"],
                                      bundle.infoDictionary[@"CFBundleVersion"],
                                      networkString];
}

- (NSString *)dashSyncVersion {
    static NSString *dashSyncCommit = nil;
    if (!dashSyncCommit) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"DashSyncCurrentCommit" ofType:nil];
        dashSyncCommit = [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSParameterAssert(dashSyncCommit);
        if (!dashSyncCommit) {
            dashSyncCommit = @"?";
        }
        // use first 7 characters of commit sha (same as GitHub)
        dashSyncCommit = dashSyncCommit.length > 7 ? [dashSyncCommit substringToIndex:7] : dashSyncCommit;
    }

    return [NSString stringWithFormat:@"DashSync %@", dashSyncCommit];
}

- (NSString *)exploreDashSyncState {
    static NSDateFormatter *dateFormatter = nil;
    if (!dateFormatter) {
        dateFormatter = [NSDateFormatter new];
        dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        dateFormatter.timeStyle = NSDateFormatterShortStyle;
    }

    NSString *prefix = NSLocalizedString(@"Last device sync", @"Explore Dash");
    SyncState state = [ExploreDashObjcWrapper syncState];
    switch (state) {
        case SyncStateInititialing:
        case SyncStateFetchingInfo:
            return [NSString stringWithFormat:@"%@: %@", prefix, NSLocalizedString(@"Fetching Info", @"Explore Dash")];
        case SyncStateSyncing:
            return [NSString stringWithFormat:@"%@: %@", prefix, NSLocalizedString(@"Syncing...", @"Explore Dash")];
        case SyncStateSynced: {
            NSDate *date = [ExploreDashObjcWrapper lastSyncTryDate];
            NSString *str = [NSString stringWithFormat:@"%@: %@", prefix, [dateFormatter stringFromDate:date]];
            return str;
        }
        case SyncStateError: {
            NSDate *date = [ExploreDashObjcWrapper lastFailedSyncDate];
            NSString *str = [NSString stringWithFormat:@"%@: %@ %@", prefix, NSLocalizedString(@"Failed to sync on", @"Explore Dash"), [dateFormatter stringFromDate:date]];
            return str;
        }
    }
    return @"";
}

- (NSString *)exploreLastServerUpdateDate {
    static NSDateFormatter *dateFormatter = nil;
    if (!dateFormatter) {
        dateFormatter = [NSDateFormatter new];
        dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        dateFormatter.timeStyle = NSDateFormatterNoStyle;
    }

    NSDate *date = [ExploreDashObjcWrapper lastServerUpdateDate];
    return [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"Last server update", @"Explore Dash"), [dateFormatter stringFromDate:date]];
}

- (NSString *)status {
    static NSDateFormatter *dateFormatter = nil;
    if (!dateFormatter) {
        dateFormatter = [NSDateFormatter new];
        dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"Mdjma" options:0 locale:[NSLocale currentLocale]];
    }

    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSPeerManager *peerManager = [DWEnvironment sharedInstance].currentChainManager.peerManager;
    DSMasternodeManager *masternodeManager = [DWEnvironment sharedInstance].currentChainManager.masternodeManager;
    DSMasternodeList *currentMasternodeList = masternodeManager.currentMasternodeList;

    NSString *rateString = [NSString stringWithFormat:NSLocalizedString(@"Rate: %@ = %@", @"ex., Rate 1 US $ = 0.000009 Dash"),
                                                      [CurrencyExchangerObjcWrapper localCurrencyStringForDashAmount:DUFFS / CurrencyExchangerObjcWrapper.localCurrencyDashPrice.doubleValue],
                                                      [CurrencyExchangerObjcWrapper stringForDashAmount:DUFFS / CurrencyExchangerObjcWrapper.localCurrencyDashPrice.doubleValue]];
    NSString *updatedString = [NSString stringWithFormat:NSLocalizedString(@"Updated: %@", @"ex., Updated: 27.12, 8:30"),
                                                         [dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:authenticationManager.secureTime]].lowercaseString];
    NSString *blockString = [NSString stringWithFormat:NSLocalizedString(@"Block #%d of %d", nil),
                                                       chain.lastSyncBlockHeight,
                                                       chain.estimatedBlockHeight];
    NSString *peersString = [NSString stringWithFormat:NSLocalizedString(@"Connected peers: %d", nil),
                                                       (int)peerManager.connectedPeerCount];
    NSString *dlPeerString = [NSString stringWithFormat:NSLocalizedString(@"Download peer: %@", @"ex., Download peer: 127.0.0.1:9999"),
                                                        peerManager.downloadPeerName ? peerManager.downloadPeerName : @"-"];
    NSString *quorumsString = [NSString stringWithFormat:NSLocalizedString(@"Quorums validated: %d/%d", nil),
                                                         (int)[currentMasternodeList validQuorumsCountOfType:DSLLMQType_50_60],
                                                         (int)[currentMasternodeList quorumsCountOfType:DSLLMQType_50_60]];

    NSString *usernameString = @"";
    if ([DWGlobalOptions sharedInstance].dashpayUsername) {
        usernameString = [NSString stringWithFormat:NSLocalizedString(@"Current user: %@", nil),
                                                    [DWGlobalOptions sharedInstance].dashpayUsername];
    }

    NSArray<NSString *> *statusLines = @[ rateString, updatedString, blockString, peersString, dlPeerString, quorumsString, usernameString ];

    return [statusLines componentsJoinedByString:@"\n"];
}

- (NSArray<NSURL *> *)logFiles {
    return [[DSLogger sharedInstance] logFiles];
}

- (void)setFixedPeer:(NSString *)fixedPeer {
    NSArray *pair = [fixedPeer componentsSeparatedByString:@":"];
    NSString *host = pair.firstObject;
    NSString *service = (pair.count > 1) ? pair[1] : @([DWEnvironment sharedInstance].currentChain.standardPort).stringValue;
    struct addrinfo hints = {0, AF_UNSPEC, SOCK_STREAM, 0, 0, 0, NULL, NULL}, *servinfo, *p;
    UInt128 addr = {.u32 = {0, 0, CFSwapInt32HostToBig(0xffff), 0}};

    NSLog(@"DNS lookup %@", host);

    if (getaddrinfo(host.UTF8String, service.UTF8String, &hints, &servinfo) == 0) {
        for (p = servinfo; p != NULL; p = p->ai_next) {
            if (p->ai_family == AF_INET) {
                addr.u64[0] = 0;
                addr.u32[2] = CFSwapInt32HostToBig(0xffff);
                addr.u32[3] = ((struct sockaddr_in *)p->ai_addr)->sin_addr.s_addr;
            }
            else {
                continue;
            }

            uint16_t port = CFSwapInt16BigToHost(((struct sockaddr_in *)p->ai_addr)->sin_port);
            char s[INET6_ADDRSTRLEN];

            if (addr.u64[0] == 0 && addr.u32[2] == CFSwapInt32HostToBig(0xffff)) {
                host = @(inet_ntop(AF_INET, &addr.u32[3], s, sizeof(s)));
            }
            else {
                host = @(inet_ntop(AF_INET6, &addr, s, sizeof(s)));
            }
            [[DWEnvironment sharedInstance].currentChainManager.peerManager setTrustedPeerHost:[NSString stringWithFormat:@"%@:%d", host, port]];
            [[DWEnvironment sharedInstance].currentChainManager.peerManager disconnect];
            [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
            break;
        }

        freeaddrinfo(servinfo);
    }
}

- (void)clearFixedPeer {
    DSPeerManager *peerManager = [DWEnvironment sharedInstance].currentChainManager.peerManager;
    [peerManager removeTrustedPeerHost];
    [peerManager disconnect];
    [peerManager connect];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self.exploreDashDatabaseState];
}

@end

NS_ASSUME_NONNULL_END

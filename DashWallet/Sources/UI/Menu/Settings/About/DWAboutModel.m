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
    NSString *networkString = @"";
    if (!DWWalletEnvironment.isMainnet) {
        networkString = [NSString stringWithFormat:@" (%@)", DWWalletEnvironment.networkDisplayName];
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

    NSString *rateString = [NSString stringWithFormat:NSLocalizedString(@"Rate: %@ = %@", @"ex., Rate 1 US $ = 0.000009 Dash"),
                                                      [CurrencyExchangerObjcWrapper localCurrencyStringForDashAmount:DUFFS / CurrencyExchangerObjcWrapper.localCurrencyDashPrice.doubleValue],
                                                      [CurrencyExchangerObjcWrapper stringForDashAmount:DUFFS / CurrencyExchangerObjcWrapper.localCurrencyDashPrice.doubleValue]];
    NSString *updatedString = [NSString stringWithFormat:NSLocalizedString(@"Updated: %@", @"ex., Updated: 27.12, 8:30"),
                                                         [dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[DWAuthenticationService shared].secureTime]].lowercaseString];
    // Block + connection lines read SwiftDashSDK SPV state (C1 cat 4) — the
    // DashSync chain heights and DSPeerManager are frozen/dead post-M6.
    NSString *blockString = [self blockSyncLine];
    NSString *spvString = [self spvConnectionLine];
    NSString *masternodeListString = [self masternodeListSyncLine];

    NSString *usernameString = @"";

#if DASHPAY
    if ([DWGlobalOptions sharedInstance].dashpayUsername) {
        usernameString = [NSString stringWithFormat:NSLocalizedString(@"Current user: %@", nil),
                                                    [DWGlobalOptions sharedInstance].dashpayUsername];
    }
#endif

    NSArray<NSString *> *statusLines = @[ rateString, updatedString, blockString, spvString, masternodeListString, usernameString ];

    return [statusLines componentsJoinedByString:@"\n"];
}

- (NSArray<NSURL *> *)logFiles {
    return [[DWLogger sharedInstance] logFiles];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self.exploreDashDatabaseState];
}

@end

NS_ASSUME_NONNULL_END

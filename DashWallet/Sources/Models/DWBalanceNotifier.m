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

#import "DWBalanceNotifier.h"

#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import <DashSync/DSLogger.h>
#import <DashSync/DSPermissionNotification.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWBalanceNotifier ()

// the nsnotificationcenter observer for wallet balance
@property (nullable, nonatomic, strong) id balanceObserver;

// the most recent balance as received by notification
@property (assign, atomic) uint64_t balance;


@end

@implementation DWBalanceNotifier

- (void)dealloc {
    if (self.balanceObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    }
}

- (void)setupNotifications {
    self.balance = UINT64_MAX; // this gets set in `updateBalance` (called in applicationDidBecomActive)

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    self.balanceObserver =
        [notificationCenter addObserverForName:DSWalletBalanceDidChangeNotification
                                        object:nil
                                         queue:nil
                                    usingBlock:^(NSNotification *_Nonnull note) {
                                        [self walletBalanceDidChangeNotification:note];
                                    }];
}

- (void)updateBalance {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.balance == UINT64_MAX) {
            self.balance = [DWEnvironment sharedInstance].currentWallet.balance;
        }
    });
}

- (void)registerForPushNotifications {
    [[NSNotificationCenter defaultCenter] postNotificationName:DSWillRequestOSPermissionNotification object:nil];
    const UNAuthorizationOptions options =
        (UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert);
    [[UNUserNotificationCenter currentNotificationCenter]
        requestAuthorizationWithOptions:options
                      completionHandler:^(BOOL granted, NSError *_Nullable error) {
                          dispatch_async(dispatch_get_main_queue(), ^{
                              [[NSNotificationCenter defaultCenter] postNotificationName:DSDidRequestOSPermissionNotification object:nil];
                          });
                          [DWGlobalOptions sharedInstance].localNotificationsEnabled = granted;
                          DSLog(@"DWBalanceNotifier: register for notifications result %@, error %@", @(granted), error);
                      }];
}

#pragma mark - Private

- (void)walletBalanceDidChangeNotification:(NSNotification *)note {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    UIApplication *application = [UIApplication sharedApplication];

    if (self.balance < wallet.balance) {
        const BOOL notificationsEnabled = [DWGlobalOptions sharedInstance].localNotificationsEnabled;
        NSString *noteText = [NSString stringWithFormat:
                                           NSLocalizedString(@"Received %@ (%@)", nil),
                                           [priceManager stringForDashAmount:wallet.balance - self.balance],
                                           [priceManager localCurrencyStringForDashAmount:wallet.balance - self.balance]];

        DSLog(@"DWBalanceNotifier: local notifications enabled = %d", notificationsEnabled);

        // send a local notification if in the background
        if (application.applicationState == UIApplicationStateBackground ||
            application.applicationState == UIApplicationStateInactive) {

            if (notificationsEnabled) {
                UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
                content.body = noteText;
                content.sound = [UNNotificationSound soundNamed:@"coinflip"];
                content.badge = @(application.applicationIconBadgeNumber + 1);

                // Deliver the notification in five seconds.
                UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger
                    triggerWithTimeInterval:1.0
                                    repeats:NO];
                UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"Now"
                                                                                      content:content
                                                                                      trigger:trigger];
                // schedule localNotification
                UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
                [center addNotificationRequest:request
                         withCompletionHandler:^(NSError *_Nullable error) {
                             if (!error) {
                                 DSLog(@"DWBalanceNotifier: sent local notification %@", note);
                             }
                         }];
            }
        }
    }

    self.balance = wallet.balance;
}

@end

NS_ASSUME_NONNULL_END

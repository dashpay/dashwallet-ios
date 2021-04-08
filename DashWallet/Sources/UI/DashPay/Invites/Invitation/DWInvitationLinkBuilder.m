//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWInvitationLinkBuilder.h"

#import "DWEnvironment.h"
#import <Firebase/Firebase.h>

#import "DSBlockchainIdentity+DWDisplayName.h"

static NSString *const AndroidBundleID = @"hashengineering.darkcoin.wallet_test";
// TODO: DP set app store id
static NSString *const iOSAppStoreID = @"1560401158";

@implementation DWInvitationLinkBuilder

+ (void)dynamicLinkFrom:(NSString *)linkString
    myBlockchainIdentity:(DSBlockchainIdentity *)myBlockchainIdentity
              completion:(void (^)(NSURL *_Nullable url))completion {
    NSString *encodedName = [[myBlockchainIdentity dw_displayNameOrUsername] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];

    NSString *displayNameParam = @"";
    if (myBlockchainIdentity.displayName.length != 0) {
        displayNameParam = [NSString stringWithFormat:@"&display-name=%@", encodedName];
    }

    NSString *avatarParam = @"";
    if (myBlockchainIdentity.avatarPath.length > 0) {
        NSString *encodedAvatar = [myBlockchainIdentity.avatarPath stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        avatarParam = [NSString stringWithFormat:@"&avatar-url=%@", encodedAvatar];
    }

    NSString *fullLink = [NSString stringWithFormat:@"%@%@%@", linkString, displayNameParam, avatarParam];

    NSURL *link = [[NSURL alloc] initWithString:fullLink];
    NSString *dynamicLinksDomainURIPrefix = @"https://invitations.dashpay.io/link";
    FIRDynamicLinkComponents *linkBuilder =
        [[FIRDynamicLinkComponents alloc] initWithLink:link
                                       domainURIPrefix:dynamicLinksDomainURIPrefix];
    linkBuilder.iOSParameters =
        [[FIRDynamicLinkIOSParameters alloc] initWithBundleID:[[NSBundle mainBundle] bundleIdentifier]];
    linkBuilder.iOSParameters.appStoreID = iOSAppStoreID;
    linkBuilder.androidParameters =
        [[FIRDynamicLinkAndroidParameters alloc] initWithPackageName:AndroidBundleID];

    linkBuilder.socialMetaTagParameters =
        [[FIRDynamicLinkSocialMetaTagParameters alloc] init];
    linkBuilder.socialMetaTagParameters.title = NSLocalizedString(@"Join Now", nil);

    NSString *urlFormat =
        [NSString
            stringWithFormat:@"https://invitations.dashpay.io/fun/invite-preview?display-name=%@%@",
                             encodedName, avatarParam];
    linkBuilder.socialMetaTagParameters.imageURL = [NSURL URLWithString:urlFormat];
    linkBuilder.socialMetaTagParameters.descriptionText =
        [NSString stringWithFormat:NSLocalizedString(@"You have been invited by %@. Start using Dash cryptocurrency.", nil),
                                   [myBlockchainIdentity dw_displayNameOrUsername]];

    [linkBuilder shortenWithCompletion:^(NSURL *_Nullable shortURL,
                                         NSArray<NSString *> *_Nullable warnings,
                                         NSError *_Nullable error) {
        if (completion) {
            completion(shortURL);
        }
    }];
}

@end

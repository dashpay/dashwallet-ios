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

#import "DPAlertViewController+DWInvite.h"

#import "DWDashPayConstants.h"
#import <DashSync/DashSync.h>

@implementation DPAlertViewController (DWInvite)

+ (DPAlertViewController *)insufficientFundsForInvitationAlert {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSString *amount = [[[priceManager stringForDashAmount:DWDP_MIN_BALANCE_TO_CREATE_INVITE]
        stringByReplacingOccurrencesOfString:DASH
                                  withString:@""]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSString *desc = [NSString stringWithFormat:
                                   NSLocalizedString(@"You need at least %@ Dash to create an invitation", nil), amount];
    DPAlertViewController *controller =
        [[DPAlertViewController alloc]
            initWithIcon:[UIImage imageNamed:@"insufficientFunds_icon"]
                   title:NSLocalizedString(@"Insufficient Wallet Balance", nil)
             description:desc];
    return controller;
}

@end

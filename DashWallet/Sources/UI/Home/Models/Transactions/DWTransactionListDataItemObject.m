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

#import "DWTransactionListDataItemObject.h"

#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWTransactionListDataItemObject

- (UIColor *)dashAmountTintColor {
    switch (self.direction) {
        case DSTransactionDirection_Moved: {
            return [UIColor dw_quaternaryTextColor];
        }
        case DSTransactionDirection_Sent: {
            return [UIColor dw_darkTitleColor];
        }
        case DSTransactionDirection_Received: {
            return [UIColor dw_dashBlueColor];
        }
        case DSTransactionDirection_NotAccountFunds: {
            return [UIColor dw_dashBlueColor];
        }
    }
}

- (NSString *)directionSymbol {
    switch (self.direction) {
        case DSTransactionDirection_Moved:
            return @"⟲";
        case DSTransactionDirection_Received:
            return @"+";
        case DSTransactionDirection_Sent:
            return @"-";
        case DSTransactionDirection_NotAccountFunds:
            return @"";
    }
}

- (nullable NSString *)stateText {
    switch (self.state) {
        case DWTransactionState_OK:
            return nil;
        case DWTransactionState_Invalid:
            return NSLocalizedString(@"Invalid", nil);
        case DWTransactionState_Locked:
            return NSLocalizedString(@"Locked", nil);
        case DWTransactionState_Processing:
            if (self.detailedDirection == DWTransactionDetailedDirection_Sent) {
                return nil;
            }
            else {
                return NSLocalizedString(@"Processing", nil);
            }
        case DWTransactionState_Confirming:
            return NSLocalizedString(@"Confirming", nil);
    }
}

- (nullable UIColor *)stateTintColor {
    switch (self.state) {
        case DWTransactionState_OK:
            return nil;
        case DWTransactionState_Invalid:
            return [UIColor dw_redColor];
        case DWTransactionState_Locked:
            return [UIColor dw_orangeColor];
        case DWTransactionState_Processing:
            return [UIColor dw_orangeColor];
        case DWTransactionState_Confirming:
            return [UIColor dw_orangeColor];
    }
}

- (NSString *)directionText {
    switch (self.transactionType) {
        case DWTransactionType_Classic: {
            switch (self.detailedDirection) {
                case DWTransactionDetailedDirection_Sent:
                    if (self.state == DWTransactionState_Processing) {
                        return NSLocalizedString(@"Sending", nil);
                    }
                    else {
                        return NSLocalizedString(@"Sent", nil);
                    }
                case DWTransactionDetailedDirection_Received:
                    return NSLocalizedString(@"Received", nil);
                case DWTransactionDetailedDirection_Moved:
                    return NSLocalizedString(@"Moved", nil);
            }
        } break;
        case DWTransactionType_Reward:
            return NSLocalizedString(@"Reward", nil);
        case DWTransactionType_MasternodeRegistration:
            return NSLocalizedString(@"Masternode Registration", nil);
        case DWTransactionType_MasternodeUpdate:
            return NSLocalizedString(@"Masternode Update", nil);
        case DWTransactionType_MasternodeRevoke:
            return NSLocalizedString(@"Masternode Revocation", nil);
        default:
            break;
    }
}

@end

NS_ASSUME_NONNULL_END

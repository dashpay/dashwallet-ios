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

#import "DWAmountSendingOptionsModel.h"

#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWAmountSendingOptionsModel ()

@property (strong, nonatomic) DSPaymentProtocolDetails *paymentDetails;
@property (assign, nonatomic) DWAmountSendOptionsModelState state;

@end

@implementation DWAmountSendingOptionsModel

- (instancetype)initWithSendingDestination:(NSString *)sendingDestination paymentDetails:(DSPaymentProtocolDetails *)paymentDetails {
    self = [super init];
    if (self) {
        _sendingDestination = [sendingDestination copy];
        _paymentDetails = paymentDetails;
    }
    return self;
}

- (void)updateWithAmount:(uint64_t)amount {

    if (amount == 0) {
        self.state = DWAmountSendOptionsModelState_None;
        return;
    }

    self.state = DWAmountSendOptionsModelState_AutoLocks;
}

@end

NS_ASSUME_NONNULL_END

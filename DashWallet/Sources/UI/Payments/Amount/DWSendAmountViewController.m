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

#import "DWSendAmountViewController.h"

#import "DWAmountModel.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWSendAmountViewController

+ (instancetype)sendControllerWithDestination:(NSString *)sendingDestination
                               paymentDetails:(nullable DSPaymentProtocolDetails *)paymentDetails {
    DWAmountModel *model = [[DWAmountModel alloc] initWithInputIntent:DWAmountInputIntent_Send
                                                   sendingDestination:sendingDestination
                                                       paymentDetails:paymentDetails];

    DWSendAmountViewController *controller = [[DWSendAmountViewController alloc] initWithModel:model];

    return controller;
}

+ (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Pay", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Pay", nil);
}

#pragma mark - Actions

- (void)actionButtonAction:(id)sender {
    BOOL inputValid = [self validateInputAmount];
    if (!inputValid) {
        return;
    }

    NSAssert(self.model.inputIntent == DWAmountInputIntent_Send, @"Inconsistent state");

    const DWAmountSendOptionsModelState state = self.model.sendingOptions.state;
    const BOOL usedInstantSend = state == DWAmountSendOptionsModelState_ProposeInstantSend &&
                                 self.model.sendingOptions.useInstantSend;
    [self.delegate sendAmountViewController:self
                             didInputAmount:self.model.amount.plainAmount
                            usedInstantSend:usedInstantSend];
}

@end

NS_ASSUME_NONNULL_END

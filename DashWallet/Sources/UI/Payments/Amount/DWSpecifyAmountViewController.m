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

#import "DWSpecifyAmountViewController.h"

#import "DWAmountModel.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWSpecifyAmountViewController

+ (instancetype)controller {
    DWAmountModel *model = [[DWAmountModel alloc] initWithInputIntent:DWAmountInputIntent_Request
                                                   sendingDestination:nil
                                                       paymentDetails:nil];

    DWSpecifyAmountViewController *controller = [[DWSpecifyAmountViewController alloc] initWithModel:model];

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

    NSAssert(self.model.inputIntent == DWAmountInputIntent_Request, @"Inconsistent state");

    [self.delegate specifyAmountViewController:self didInputAmount:self.model.amount.plainAmount];
}

@end

NS_ASSUME_NONNULL_END

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

#import "DWConfirmPaymentViewController.h"

#import "DWConfirmPaymentContentView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWConfirmPaymentViewController ()

@property (null_resettable, nonatomic, strong) DWConfirmPaymentContentView *confirmPaymentView;

@end

@implementation DWConfirmPaymentViewController

+ (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Send", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (void)actionButtonAction:(id)sender {
    [self.delegate confirmPaymentViewControllerDidConfirm:self];
}

- (void)setPaymentOutput:(nullable DWPaymentOutput *)paymentOutput {
    _paymentOutput = paymentOutput;

    [self.confirmPaymentView setPaymentOutput:paymentOutput];
}

#pragma mark - Private

- (void)setupView {
    [self setModalTitle:NSLocalizedString(@"Confirm", nil)];

    [self setupModalContentView:self.confirmPaymentView];
}

- (DWConfirmPaymentContentView *)confirmPaymentView {
    if (_confirmPaymentView == nil) {
        _confirmPaymentView = [[DWConfirmPaymentContentView alloc] initWithFrame:CGRectZero];
    }

    return _confirmPaymentView;
}

@end

NS_ASSUME_NONNULL_END

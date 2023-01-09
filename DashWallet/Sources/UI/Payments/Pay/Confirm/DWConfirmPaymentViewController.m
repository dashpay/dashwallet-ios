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
@property (nonatomic, strong) NSTimer *sendingTimer;
@property (nonatomic, assign) uint8_t period;

@end

@implementation DWConfirmPaymentViewController

+ (BOOL)isActionButtonInNavigationBar {
    return NO;
}

- (NSString *)actionButtonTitle {
    return [self.model hasCommonName] ? NSLocalizedString(@"Pay", nil) : NSLocalizedString(@"Send", nil);
}

- (NSString *)actionButtonDisabledTitle {
    if ([self.model hasCommonName]) {
        switch (self.period) {
            case 1:
                return NSLocalizedString(@"Paying.", @"2 out of 4 in the Paying Animation");
            case 2:
                return NSLocalizedString(@"Paying..", @"3 out of 4 in the Paying Animation");
            case 3:
                return NSLocalizedString(@"Paying...", @"4 out of 4 in the Paying Animation");
            default:
                return NSLocalizedString(@"Paying", @"1 out of 4 in the Paying Animation");
        }
    }
    else {
        switch (self.period) {
            case 1:
                return NSLocalizedString(@"Sending.", @"2 out of 4 in the Sending Animation");
            case 2:
                return NSLocalizedString(@"Sending..", @"3 out of 4 in the Sending Animation");
            case 3:
                return NSLocalizedString(@"Sending...", @"4 out of 4 in the Sending Animation");
            default:
                return NSLocalizedString(@"Sending", @"1 out of 4 in the Sending Animation");
        }
    }
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^__nullable)(void))completion {
    [self.delegate confirmPaymentViewControllerDidCancel:self];

    [super dismissViewControllerAnimated:flag completion:completion];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _period = 0;
    _sendingEnabled = YES;

    [self setupView];
}

- (void)dealloc {
    [self.sendingTimer invalidate];
}

- (void)setSendingEnabled:(BOOL)sendingEnabled {
    if (_sendingEnabled && !sendingEnabled) {
        __weak typeof(self) weakSelf = self;
        self.sendingTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                            repeats:YES
                                                              block:^(NSTimer *_Nonnull timer) {
                                                                  __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                  if (!strongSelf) {
                                                                      return;
                                                                  }

                                                                  strongSelf.period++;
                                                                  strongSelf.period %= 4;
                                                                  [strongSelf reloadActionButtonTitles];
                                                              }];
    }
    else if (!_sendingEnabled && sendingEnabled) {
        [self.sendingTimer invalidate];
    }
    _sendingEnabled = sendingEnabled;
    self.actionButton.enabled = sendingEnabled;
    self.interactiveTransitionAllowed = sendingEnabled;
}

- (void)actionButtonAction:(id)sender {
    [self setSendingEnabled:NO];
    [self.delegate confirmPaymentViewControllerDidConfirm:self];
}

- (nullable id<DWConfirmPaymentViewProtocol>)model {
    return self.confirmPaymentView.model;
}

- (void)setModel:(nullable id<DWConfirmPaymentViewProtocol>)model {
    self.confirmPaymentView.model = model;
    [self reloadActionButtonTitles];
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

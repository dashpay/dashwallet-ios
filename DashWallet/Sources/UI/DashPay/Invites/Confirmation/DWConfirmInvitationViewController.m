//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWConfirmInvitationViewController.h"

#import "DWConfirmInvitationContentView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWConfirmInvitationViewController ()

@property (nonatomic, strong) DWConfirmInvitationContentView *confirmView;

@end

NS_ASSUME_NONNULL_END

@implementation DWConfirmInvitationViewController

+ (BOOL)isActionButtonInNavigationBar {
    return NO;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Confirm", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setModalTitle:NSLocalizedString(@"Confirm", nil)];

    self.actionButton.enabled = NO;

    self.confirmView = [[DWConfirmInvitationContentView alloc] initWithFrame:CGRectZero];
    [self.confirmView.confirmationCheckbox addTarget:self
                                              action:@selector(confirmationCheckboxAction:)
                                    forControlEvents:UIControlEventValueChanged];

    [self setupModalContentView:self.confirmView];
}

- (void)actionButtonAction:(id)sender {
    self.actionButton.enabled = NO;
    [self.delegate confirmInvitationViewControllerDidConfirm:self];
}

- (void)confirmationCheckboxAction:(DWCheckbox *)sender {
    self.actionButton.enabled = sender.isOn;
}

@end
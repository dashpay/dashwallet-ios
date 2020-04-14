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

#import "DWConfirmUsernameViewController.h"

#import "DWConfirmUsernameContentView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWConfirmUsernameViewController ()

@property (nonatomic, strong) DWConfirmUsernameContentView *confirmUsernameView;

@end

NS_ASSUME_NONNULL_END

@implementation DWConfirmUsernameViewController

- (instancetype)initWithUsername:(NSString *)username {
    self = [super init];
    if (self) {
        _username = [username copy];
    }
    return self;
}

+ (BOOL)isActionButtonInNavigationBar {
    return NO;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Confirm & Pay", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setModalTitle:NSLocalizedString(@"Confirm", nil)];

    self.actionButton.enabled = NO;

    self.confirmUsernameView = [[DWConfirmUsernameContentView alloc] initWithFrame:CGRectZero];
    self.confirmUsernameView.username = self.username;
    [self.confirmUsernameView.confirmationCheckbox addTarget:self
                                                      action:@selector(confirmationCheckboxAction:)
                                            forControlEvents:UIControlEventValueChanged];

    [self setupModalContentView:self.confirmUsernameView];
}

- (void)actionButtonAction:(id)sender {
    self.actionButton.enabled = NO;
    [self.delegate confirmUsernameViewControllerDidConfirm:self];
}

- (void)confirmationCheckboxAction:(DWCheckbox *)sender {
    self.actionButton.enabled = sender.isOn;
}

@end

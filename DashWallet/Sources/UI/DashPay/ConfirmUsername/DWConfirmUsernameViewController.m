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

@interface DWConfirmUsernameViewController ()

@end

@implementation DWConfirmUsernameViewController


+ (BOOL)isActionButtonInNavigationBar {
    return NO;
}

- (NSString *)actionButtonTitle {
    // TODO: localize
    return @"Confirm & Pay";
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setModalTitle:NSLocalizedString(@"Confirm", nil)];

    UIView *contentView = [[NSBundle mainBundle] loadNibNamed:@"ConfirmUsernameView" owner:self options:nil].firstObject;
    [self setupModalContentView:contentView];
}

- (void)actionButtonAction:(id)sender {
    self.actionButton.enabled = NO;
    [self.delegate confirmUsernameViewControllerDidConfirm:self];
}

@end

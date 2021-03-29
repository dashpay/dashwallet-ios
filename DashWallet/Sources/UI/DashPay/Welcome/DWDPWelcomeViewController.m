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

#import "DWDPWelcomeViewController.h"

#import "DWDPWelcomeCollectionViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPWelcomeViewController ()

@property (nonatomic, strong) DWDPWelcomeCollectionViewController *collection;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPWelcomeViewController

+ (BOOL)isActionButtonInNavigationBar {
    return NO;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Continue", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.actionButton.enabled = YES;
    self.view.backgroundColor = [UIColor dw_backgroundColor];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self setupContentView:contentView];

    DWDPWelcomeCollectionViewController *collection = [[DWDPWelcomeCollectionViewController alloc] init];
    [self dw_embedChild:collection inContainer:contentView];
    self.collection = collection;
}

- (void)actionButtonAction:(id)sender {
    if ([self.collection canSwitchToNext]) {
        [self.collection switchToNext];
    }
    else {
        [self.delegate welcomeViewControllerDidFinish:self];
    }
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

@end

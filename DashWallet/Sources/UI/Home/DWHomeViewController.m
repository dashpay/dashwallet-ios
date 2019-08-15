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

#import "DWHomeViewController.h"

#import "DWHomeModel.h"
#import "DWHomeView.h"
#import "DWHomeViewController+DWJailbreakCheck.h"
#import "DWHomeViewController+DWShortcuts.h"
#import "DWHomeViewController+DWTxFilter.h"
#import "DWNavigationController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeViewController () <DWHomeViewDelegate, DWShortcutsActionDelegate>

@property (strong, nonatomic) DWHomeView *view;

@end

@implementation DWHomeViewController

@dynamic view;
@synthesize model = _model;

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)loadView {
    CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWHomeView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.delegate = self;
    self.view.shortcutsDelegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
    [self performJailbreakCheck];

    // TODO: impl migration stuff from protectedViewDidAppear of DWRootViewController
    // TODO: check if wallet is watchOnly and show info about it
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - DWHomeViewDelegate

- (void)homeView:(DWHomeView *)homeView showTxFilter:(UIView *)sender {
    [self showTxFilterWithSender:sender];
}

- (void)homeView:(DWHomeView *)homeView payButtonAction:(UIButton *)sender {
    [self.delegate homeViewController:self payButtonAction:sender];
}

- (void)homeView:(DWHomeView *)homeView receiveButtonAction:(UIButton *)sender {
    [self.delegate homeViewController:self receiveButtonAction:sender];
}

#pragma mark - DWShortcutsActionDelegate

- (void)shortcutsView:(UIView *)view didSelectAction:(DWShortcutAction *)action sender:(UIView *)sender {
    [self performActionForShortcut:action sender:sender];
}

#pragma mark - Private

- (DWHomeModel *)model {
    if (_model == nil) {
        _model = [[DWHomeModel alloc] init];
    }

    return _model;
}

- (void)setupView {
    UIImage *logoImage = [UIImage imageNamed:@"dash_logo"];
    NSParameterAssert(logoImage);
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:logoImage];

    self.view.model = self.model;
}

@end

NS_ASSUME_NONNULL_END

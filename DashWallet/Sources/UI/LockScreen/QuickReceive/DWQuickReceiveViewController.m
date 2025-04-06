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

#import "DWQuickReceiveViewController.h"

#import "DWUIKit.h"
#import "SFSafariViewController+DashWallet.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const DASH_WEBSITE = @"https://dash.org";

@interface DWQuickReceiveViewController () // <DWReceiveViewControllerDelegate>

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UIView *receiveContentView;

@property (nonatomic, strong) id<DWReceiveModelProtocol> receiveModel;
@property (nonatomic, strong) DWReceiveViewController *receiveController;

@end

@implementation DWQuickReceiveViewController

+ (UIViewController *)controllerWithModel:(id<DWReceiveModelProtocol>)receiveModel {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"QuickReceive" bundle:nil];
    DWQuickReceiveViewController *controller = [storyboard instantiateInitialViewController];
    controller.receiveModel = receiveModel;

    DWModalNavigationController *navigationController =
        [[DWModalNavigationController alloc] initWithRootViewController:controller];
    [navigationController setCancelButtonHidden:NO];
    return navigationController;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - Actions

- (IBAction)websiteButtonAction:(id)sender {
    NSURL *url = [NSURL URLWithString:DASH_WEBSITE];
    NSParameterAssert(url);
    if (!url) {
        return;
    }

    SFSafariViewController *controller = [SFSafariViewController dw_controllerWithURL:url];
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - DWReceiveViewControllerDelegate

- (void)receiveViewControllerExitButtonAction:(DWReceiveViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Private

- (void)setupView {
    self.titleLabel.text = NSLocalizedString(@"Scan this to Pay", @"A title of the quick receive screen");

    DWReceiveViewController *receiveController = [[DWReceiveViewController alloc] initWithModel:self.receiveModel];
    //    receiveController.delegate = self;
    receiveController.allowedToImportPrivateKey = NO;

    [self dw_embedChild:receiveController inContainer:self.receiveContentView];
    self.receiveController = receiveController;
}

@end

NS_ASSUME_NONNULL_END

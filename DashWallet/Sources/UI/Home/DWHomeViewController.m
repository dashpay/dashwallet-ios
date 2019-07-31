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
#import "DWNavigationController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeViewController ()

@property (null_resettable, strong, nonatomic) DWHomeModel *model;

@property (strong, nonatomic) DWHomeView *view;

@end

@implementation DWHomeViewController

@dynamic view;

+ (UIViewController *)controllerEmbededInNavigation {
    DWHomeViewController *controller = [[DWHomeViewController alloc] init];
    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];

    return navigationController;
}

- (void)loadView {
    CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWHomeView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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

- (void)performJailbreakCheck {
    if (!self.model.isJailbroken) {
        return;
    }

    NSString *title = NSLocalizedString(@"WARNING", nil);
    NSString *message = nil;
    UIAlertAction *mainAction = nil;

    if (!self.model.isWalletEmpty) {
        message = NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                     "Any 'jailbreak' app can access any other app's keychain data "
                                     "(and steal your dash). "
                                     "Wipe this wallet immediately and restore on a secure device.",
                                    nil);
        mainAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Wipe", nil)
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action){
                        // TODO: Show wipe wallet screen (to input seed phrase)
                    }];
    }
    else {
        message = NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                     "Any 'jailbreak' app can access any other app's keychain data "
                                     "(and steal your dash).",
                                    nil);
        mainAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Close App", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                    }];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *ignoreAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ignore", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:ignoreAction];

    [alert addAction:mainAction];

    [self presentViewController:alert animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

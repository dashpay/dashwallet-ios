//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWUpholdMainViewController.h"

#import "DWBaseViewController.h"
#import "DWUIKit.h"
#import "DWUpholdBuyViewController.h"
#import "DWUpholdClient.h"
#import "DWUpholdMainModel.h"
#import "DWUpholdOLDTransferViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdMainViewController () <DWUpholdTransferViewControllerDelegate, DWUpholdBuyViewControllerDelegate>

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *balanceLabel;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *balanceActivityIndicator;
@property (strong, nonatomic) IBOutlet UIButton *retryButton;
@property (strong, nonatomic) IBOutlet UIButton *transferButton;
@property (strong, nonatomic) IBOutlet UIButton *buyButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@property (strong, nonatomic) DWUpholdMainModel *model;

@end

@implementation DWUpholdMainViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdMainStoryboard" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (DWUpholdMainModel *)model {
    if (!_model) {
        _model = [[DWUpholdMainModel alloc] init];
    }
    return _model;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];

    [self.retryButton setTitle:NSLocalizedString(@"Retry", nil) forState:UIControlStateNormal];
    [self.transferButton setTitle:NSLocalizedString(@"Transfer from Uphold", nil) forState:UIControlStateNormal];
    [self.buyButton setTitle:NSLocalizedString(@"Buy Dash", nil) forState:UIControlStateNormal];

    self.contentBottomConstraint.constant = [DWBaseViewController deviceSpecificBottomPadding];

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(contentSizeCategoryDidChangeNotification)
                               name:UIContentSizeCategoryDidChangeNotification
                             object:nil];

    [notificationCenter addObserver:self
                           selector:@selector(upholdClientUserDidLogoutNotification:)
                               name:DWUpholdClientUserDidLogoutNotification
                             object:nil];

    [notificationCenter addObserver:self.model
                           selector:@selector(fetch)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];

    [self mvvm_observe:@"self.model.state"
                  with:^(typeof(self) self, NSNumber *value) {
                      switch (self.model.state) {
                          case DWUpholdMainModelState_Loading: {
                              self.titleLabel.text = NSLocalizedString(@"Your Uphold account Dash balance is", nil);
                              [self.balanceActivityIndicator startAnimating];
                              self.balanceLabel.hidden = YES;
                              self.retryButton.hidden = YES;
                              self.transferButton.enabled = NO;
                              self.buyButton.enabled = NO;

                              break;
                          }
                          case DWUpholdMainModelState_Done: {
                              self.titleLabel.text = NSLocalizedString(@"Your Uphold account Dash balance is", nil);
                              [self.balanceActivityIndicator stopAnimating];
                              self.balanceLabel.hidden = NO;
                              self.balanceLabel.attributedText = [self.model availableDashString];
                              self.retryButton.hidden = YES;
                              self.transferButton.enabled = YES;
                              self.buyButton.enabled = YES;

                              break;
                          }
                          case DWUpholdMainModelState_Failed: {
                              self.titleLabel.text = NSLocalizedString(@"Something went wrong", nil);
                              [self.balanceActivityIndicator stopAnimating];
                              self.balanceLabel.hidden = YES;
                              self.retryButton.hidden = NO;
                              self.transferButton.enabled = NO;
                              self.buyButton.enabled = NO;

                              break;
                          }
                      }
                  }];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    UINavigationItem *navigationItem = self.parentViewController.navigationItem;
    UIBarButtonItem *rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Log Out", nil)
                                                                           style:UIBarButtonItemStylePlain
                                                                          target:self
                                                                          action:@selector(logOutButtonAction:)];
    [navigationItem setRightBarButtonItem:rightBarButtonItem animated:YES];

    [self.model fetch];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    UINavigationItem *navigationItem = self.parentViewController.navigationItem;
    [navigationItem setRightBarButtonItem:nil animated:YES];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Actions

- (IBAction)retryButtonAction:(id)sender {
    [self.model fetch];
}

- (IBAction)transferButtonAction:(id)sender {
    DWUpholdOLDTransferViewController *controller = [DWUpholdOLDTransferViewController controllerWithCard:self.model.dashCard];
    controller.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

- (IBAction)buyButtonAction:(id)sender {
    NSURL *url = [self.model buyDashURL];
    if (!url) {
        return;
    }

    [self openSafariAppWithURL:url];
}

- (void)logOutButtonAction:(id)sender {
    [self.model logOut];
    [self.delegate upholdMainViewControllerUserDidLogout:self];
}

#pragma mark - DWUpholdTransferViewControllerDelegate

- (void)upholdTransferViewControllerDidFinish:(DWUpholdOLDTransferViewController *)controller {
    [self.model fetch];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)upholdTransferViewControllerDidFinish:(DWUpholdOLDTransferViewController *)controller
                           openTransactionURL:(NSURL *)url {
    [self.model fetch];
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self openSafariAppWithURL:url];
                                   }];
}

- (void)upholdTransferViewControllerDidCancel:(DWUpholdOLDTransferViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - DWUpholdBuyViewControllerDelegate

- (void)upholdBuyViewControllerDidCancel:(DWUpholdBuyViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)upholdBuyViewControllerDidFinish:(DWUpholdBuyViewController *)controller {
    [self.model fetch];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Private

- (void)reloadAttributedData {
    if (self.model.state == DWUpholdMainModelState_Done) {
        self.balanceLabel.attributedText = [self.model availableDashString];
    }
}

- (void)openSafariAppWithURL:(NSURL *)url {
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)upholdClientUserDidLogoutNotification:(NSNotification *)notification {
    if ([self.presentedViewController isKindOfClass:DWUpholdOLDTransferViewController.class]) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end

NS_ASSUME_NONNULL_END

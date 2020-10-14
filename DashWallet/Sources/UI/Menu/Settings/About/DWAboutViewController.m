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

#import "DWAboutViewController.h"

#import <StoreKit/StoreKit.h>

#import "DWAboutModel.h"
#import "DWEnvironment.h"
#import "DWSecurityMenuModel.h"
#import "DWUIKit.h"
#import "DWWindow.h"
#import "SFSafariViewController+DashWallet.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAboutViewController ()

@property (strong, nonatomic) IBOutlet UIImageView *dashLogoImageView;
@property (strong, nonatomic) IBOutlet UILabel *appVersionLabel;
@property (strong, nonatomic) IBOutlet UILabel *dashSyncVersionLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;

@property (strong, nonatomic) IBOutlet UIButton *repositoryURLButton;

@property (strong, nonatomic) IBOutlet UILabel *rateReviewLabel;
@property (strong, nonatomic) IBOutlet UIButton *rateReviewButton;
@property (strong, nonatomic) IBOutlet UIButton *contactSupportButton;
@property (strong, nonatomic) IBOutlet UILabel *copyrightLabel;

@property (strong, nonatomic) DWAboutModel *model;

@property (nullable, nonatomic, weak) UIAlertController *techInfoAlert;

@end

@implementation DWAboutViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"About" bundle:nil];
    DWAboutViewController *controller = [storyboard instantiateInitialViewController];
    controller.hidesBottomBarWhenPushed = YES;
    controller.title = NSLocalizedString(@"About", nil);

    return controller;
}

- (DWAboutModel *)model {
    if (!_model) {
        _model = [[DWAboutModel alloc] init];
    }
    return _model;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.dashLogoImageView.tintColor = [UIColor dw_dashBlueColor];
    self.appVersionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
    self.dashSyncVersionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    self.rateReviewLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    self.copyrightLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];

    self.appVersionLabel.text = [self.model appVersion];
    self.dashSyncVersionLabel.text = [self.model dashSyncVersion];
    self.descriptionLabel.text = NSLocalizedString(@"This app is open source:", nil);
    [self.repositoryURLButton setTitle:@"https://github.com/dashevo/dashwallet-ios" forState:UIControlStateNormal];
    self.rateReviewLabel.text = NSLocalizedString(@"Help us improve your experience", nil);
    [self.rateReviewButton setTitle:NSLocalizedString(@"Review & Rate the app", nil) forState:UIControlStateNormal];
    [self.contactSupportButton setTitle:NSLocalizedString(@"Contact Support", nil) forState:UIControlStateNormal];
    self.copyrightLabel.text = NSLocalizedString(@"Copyright © 2020 Dash Core", nil);

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(updateStatusNotification:)
                               name:DSTransactionManagerTransactionStatusDidChangeNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateStatusNotification:)
                               name:DSChainNewChainTipBlockNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateStatusNotification:)
                               name:DSPeerManagerDownloadPeerDidChangeNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateStatusNotification:)
                               name:DSPeerManagerConnectedPeersDidChangeNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateStatusNotification:)
                               name:DSQuorumListDidChangeNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(deviceDidShakeNotification:)
                               name:DWDeviceDidShakeNotification
                             object:nil];

    [self updateStatusNotification:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark Actions

- (IBAction)respositoryURLAction:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://github.com/dashevo/dashwallet-ios?files=1"];
    [self displaySafariControllerWithURL:url];
}

- (IBAction)rateReviewAction:(id)sender {
    [SKStoreReviewController requestReview];
}

- (IBAction)contactSupportButtonAction:(id)sender {
    NSURL *url = [DWAboutModel supportURL];
    [self displaySafariControllerWithURL:url];
}

#pragma mark - Notifications

- (void)updateStatusNotification:(nullable NSNotification *)sender {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");
    self.techInfoAlert.message = [self.model status];
}

- (void)deviceDidShakeNotification:(NSNotification *)sender {
    NSString *techInfo = [self.model status];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@""
                                                                   message:techInfo
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *copyAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Copy", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [UIPasteboard generalPasteboard].string = [self.model status];
                }];
    [alert addAction:copyAction];

    UIAlertAction *copyLogs = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Copy Logs", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self performLogsCopy];
                }];
    [alert addAction:copyLogs];

    UIAlertAction *setPeerAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Manage Trusted Node", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self setFixedPeer];
                }];
    [alert addAction:setPeerAction];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil];
    [alert addAction:okAction];
    alert.preferredAction = okAction;

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark Private

- (void)displaySafariControllerWithURL:(NSURL *)url {
    NSParameterAssert(url);
    if (!url) {
        return;
    }

    SFSafariViewController *safariViewController = [SFSafariViewController dw_controllerWithURL:url];
    [self presentViewController:safariViewController animated:YES completion:nil];
}

- (void)performLogsCopy {
    NSArray *dataToShare = [self.model logFiles];
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:dataToShare
                                                                                         applicationActivities:nil];
    [self presentViewController:activityViewController animated:YES completion:nil];
}

- (void)setFixedPeer {
    if (![[DWEnvironment sharedInstance].currentChainManager.peerManager trustedPeerHost]) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:nil
                             message:NSLocalizedString(@"Set a trusted node", nil)
                      preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = NSLocalizedString(@"Node IP", nil);
            textField.textColor = [UIColor darkTextColor];
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
            textField.borderStyle = UITextBorderStyleRoundedRect;
        }];

        UIAlertAction *cancelButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Cancel", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:cancelButton];

        UIAlertAction *trustButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"OK", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        UITextField *ipField = alert.textFields.firstObject;
                        NSString *fixedPeer = ipField.text;
                        [self.model setFixedPeer:fixedPeer];
                    }];
        [alert addAction:trustButton];
        alert.preferredAction = trustButton;

        [self presentViewController:alert animated:YES completion:nil];
    }
    else {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:nil
                             message:NSLocalizedString(@"Clear trusted node?", nil)
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *cancelButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Cancel", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:cancelButton];

        UIAlertAction *clearButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Clear", nil)
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {
                        [self.model clearFixedPeer];
                    }];
        [alert addAction:clearButton];

        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end

NS_ASSUME_NONNULL_END

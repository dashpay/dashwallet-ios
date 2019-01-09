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

#import "DWAboutViewController.h"

#import <SafariServices/SafariServices.h>

#import "BRBubbleView.h"
#import "DWAboutModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAboutViewController ()

@property (strong, nonatomic) IBOutlet UIView *mainContentView;
@property (strong, nonatomic) IBOutlet UILabel *mainTitleLabel;
@property (strong, nonatomic) IBOutlet UIButton *statusButton;
@property (strong, nonatomic) IBOutlet UIButton *logsCopyButton;

@property (strong, nonatomic) DWAboutModel *model;

@end

@implementation DWAboutViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"AboutStoryboard" bundle:nil];
    DWAboutViewController *controller = [storyboard instantiateInitialViewController];

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

#if DEBUG
    self.logsCopyButton.hidden = NO;
#endif

    self.mainTitleLabel.text = [self.model mainTitle];

    [self.mainContentView.gestureRecognizers.firstObject addTarget:self action:@selector(aboutAction:)];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateStatusNotification:)
                                                 name:DSTransactionManagerTransactionStatusDidChangeNotification
                                               object:nil];
    [self updateStatusNotification:nil];
}

#pragma mark Actions

- (void)aboutAction:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://github.com/dashevo/dashwallet-ios?files=1"];
    [self displaySafariControllerWithURL:url];
}

- (IBAction)contactSupportButtonAction:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://support.dash.org/en/support/solutions"];
    [self displaySafariControllerWithURL:url];
}

- (IBAction)logsCopyButtonAction:(id)sender {
    [self.model performCopyLogs];

    CGPoint center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    BRBubbleView *popup = [[[BRBubbleView
        viewWithText:NSLocalizedString(@"copied", nil)
              center:center]
        popIn]
        popOutAfterDelay:2.0];
    [self.view addSubview:popup];
}

- (IBAction)setFixedPeerButtonAction:(id)sender {
    if (![[NSUserDefaults standardUserDefaults] stringForKey:SETTINGS_FIXED_PEER_KEY]) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:nil
                             message:NSLocalizedString(@"set a trusted node", nil)
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = NSLocalizedString(@"node ip", nil);
            textField.textColor = [UIColor darkTextColor];
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
            textField.borderStyle = UITextBorderStyleRoundedRect;
        }];
        UIAlertAction *cancelButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"cancel", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        UIAlertAction *trustButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"trust", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        UITextField *ipField = alert.textFields.firstObject;
                        NSString *fixedPeer = ipField.text;
                        [self.model setFixedPeer:fixedPeer];
                    }];
        [alert addAction:trustButton];
        [alert addAction:cancelButton];
        [self presentViewController:alert animated:YES completion:nil];
    }
    else {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:nil
                             message:NSLocalizedString(@"clear trusted node?", nil)
                      preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancelButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"cancel", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        UIAlertAction *clearButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"clear", nil)
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {
                        [self.model clearFixedPeer];
                    }];
        [alert addAction:clearButton];
        [alert addAction:cancelButton];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)updateStatusNotification:(nullable NSNotification *)sender {
    [self.statusButton setTitle:[self.model status] forState:UIControlStateNormal];
}

#pragma mark Private

- (void)displaySafariControllerWithURL:(NSURL *)url {
    NSParameterAssert(url);
    if (!url) {
        return;
    }

    SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:url];
    [self presentViewController:safariViewController animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

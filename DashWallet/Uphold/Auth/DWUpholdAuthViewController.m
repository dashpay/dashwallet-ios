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

#import "DWUpholdAuthViewController.h"

#import <AuthenticationServices/AuthenticationServices.h>
#import <SafariServices/SafariServices.h>

#import "DWAppDelegate.h"
#import "DWUpholdClient.h"
#import "SFSafariViewController+DashWallet.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdAuthViewController ()

@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property (strong, nonatomic) IBOutlet UILabel *firstDescriptionLabel;
@property (strong, nonatomic) IBOutlet UILabel *secondDescriptionLabel;
@property (strong, nonatomic) IBOutlet UIButton *linkButton;

@property (nullable, strong, nonatomic) id authenticationSession;

@end

@implementation DWUpholdAuthViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdAuthStoryboard" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.firstDescriptionLabel.text = NSLocalizedString(@"Buy Dash with Uphold account", nil);
    self.secondDescriptionLabel.text = NSLocalizedString(@"Transfer Dash from your Uphold account to this wallet", nil);
    [self.linkButton setTitle:NSLocalizedString(@"Link Uphold Account", nil) forState:UIControlStateNormal];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveURLNotification:)
                                                 name:BRURLNotification
                                               object:nil];
}

#pragma mark - Actions

- (IBAction)linkUpholdAccountButtonAction:(id)sender {
    self.linkButton.userInteractionEnabled = NO;
    
    NSURL *url = [[DWUpholdClient sharedInstance] startAuthRoutineByURL];

    NSString *callbackURLScheme = @"dashwallet://";
    __weak typeof(self) weakSelf = self;
    void (^completionHandler)(NSURL *_Nullable callbackURL, NSError *_Nullable error) = ^(NSURL *_Nullable callbackURL, NSError *_Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (callbackURL) {
            [strongSelf handleCallbackURL:callbackURL];
        }
        strongSelf.linkButton.userInteractionEnabled = YES;
    };

    if (@available(iOS 12.0, *)) {
        ASWebAuthenticationSession *authenticationSession =
            [[ASWebAuthenticationSession alloc] initWithURL:url
                                          callbackURLScheme:callbackURLScheme
                                          completionHandler:completionHandler];
        [authenticationSession start];
        self.authenticationSession = authenticationSession;
    }
    else if (@available(iOS 11.0, *)) {
        SFAuthenticationSession *authenticationSession =
            [[SFAuthenticationSession alloc] initWithURL:url
                                       callbackURLScheme:callbackURLScheme
                                       completionHandler:completionHandler];
        [authenticationSession start];
        self.authenticationSession = authenticationSession;
    }
    else {
        SFSafariViewController *controller = [SFSafariViewController dw_controllerWithURL:url];
        [self presentViewController:controller animated:YES completion:nil];
    }
}

- (void)didReceiveURLNotification:(NSNotification *)n {
    NSURL *url = n.userInfo[@"url"];
    [self handleCallbackURL:url];
}

- (void)handleCallbackURL:(NSURL *)url {
    if (![url.absoluteString containsString:@"uphold"]) {
        return;
    }

    self.linkButton.hidden = YES;
    [self.activityIndicatorView startAnimating];

    if (@available(iOS 11.0, *)) {
        self.authenticationSession = nil;
    }
    else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }

    __weak typeof(self) weakSelf = self;
    [[DWUpholdClient sharedInstance] completeAuthRoutineWithURL:url completion:^(BOOL success) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (success) {
            [strongSelf.delegate upholdAuthViewControllerDidAuthorize:strongSelf];
        }
        else {
            strongSelf.linkButton.hidden = NO;
            [strongSelf.activityIndicatorView stopAnimating];
        }
    }];
}

@end

NS_ASSUME_NONNULL_END

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

#import "DWUIKit.h"
#import "DWUpholdAuthURLNotification.h"
#import "DWUpholdClient.h"
#import "SFSafariViewController+DashWallet.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdAuthViewController () <ASWebAuthenticationPresentationContextProviding>

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
    self.firstDescriptionLabel.textColor = [UIColor dw_darkTitleColor];
    self.secondDescriptionLabel.textColor = [UIColor dw_darkTitleColor];
    self.firstDescriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    self.secondDescriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    [self.linkButton setTitle:NSLocalizedString(@"Link Uphold Account", nil) forState:UIControlStateNormal];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveURLNotification:)
                                                 name:DWUpholdAuthURLNotification
                                               object:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (IBAction)linkUpholdAccountButtonAction:(id)sender {
    self.linkButton.userInteractionEnabled = NO;

    NSURL *url = [[DWUpholdClient sharedInstance] startAuthRoutineByURL];

    // Starting iOS 14.5 `callbackURLScheme` is required to have the following format:
    // "The provided scheme is not valid. A scheme should not include special characters such as ":" or "/"."
    // See https://developer.apple.com/forums/thread/679251
    NSString *callbackURLScheme = [@"dashwallet://" stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
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

    ASWebAuthenticationSession *authenticationSession =
        [[ASWebAuthenticationSession alloc] initWithURL:url
                                      callbackURLScheme:callbackURLScheme
                                      completionHandler:completionHandler];
    if (@available(iOS 13.0, *)) {
        authenticationSession.presentationContextProvider = self;
    }
    [authenticationSession start];
    self.authenticationSession = authenticationSession;
}

- (void)didReceiveURLNotification:(NSNotification *)n {
    NSURL *url = (NSURL *)n.object;
    NSParameterAssert(url);
    if (!url) {
        return;
    }

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
    [[DWUpholdClient sharedInstance] completeAuthRoutineWithURL:url
                                                     completion:^(BOOL success) {
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

#pragma mark - ASWebAuthenticationPresentationContextProviding

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session API_AVAILABLE(ios(13.0)) {
    return self.view.window;
}

@end

NS_ASSUME_NONNULL_END

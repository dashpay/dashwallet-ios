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

#import "DWAppDelegate.h"
#import "DWUpholdClient.h"
#import "SFSafariViewController+DashWallet.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdAuthViewController ()

@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property (strong, nonatomic) IBOutlet UIButton *linkButton;

@end

@implementation DWUpholdAuthViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdAuthStoryboard" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.linkButton setTitle:NSLocalizedString(@"Link Uphold Account", nil) forState:UIControlStateNormal];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveURLNotification:)
                                                 name:BRURLNotification
                                               object:nil];
}

#pragma mark - Actions

- (IBAction)linkUpholdAccountButtonAction:(id)sender {
    NSURL *url = [[DWUpholdClient sharedInstance] startAuthRoutineByURL];
    SFSafariViewController *controller = [SFSafariViewController dw_controllerWithURL:url];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)didReceiveURLNotification:(NSNotification *)n {
    NSURL *url = n.userInfo[@"url"];
    if (![url.absoluteString containsString:@"uphold"]) {
        return;
    }

    self.linkButton.hidden = YES;
    [self.activityIndicatorView startAnimating];

    [self dismissViewControllerAnimated:YES completion:nil];

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

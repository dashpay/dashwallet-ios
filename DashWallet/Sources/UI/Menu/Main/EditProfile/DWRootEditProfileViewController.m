//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWRootEditProfileViewController.h"

#import "DWEditProfileViewController.h"
#import "DWEnvironment.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWRootEditProfileViewController () <DWEditProfileViewControllerDelegate>

@property (nonatomic, strong) DWEditProfileViewController *editController;
@property (readonly, nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;

@end

NS_ASSUME_NONNULL_END

@implementation DWRootEditProfileViewController

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Save", nil);
}

- (DSBlockchainIdentity *)blockchainIdentity {
    return self.editController.blockchainIdentity;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Edit Profile", nil);

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                            target:self
                                                                            action:@selector(cancelButtonAction)];
    self.navigationItem.leftBarButtonItem = cancel;

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self setupContentView:contentView];

    self.editController = [[DWEditProfileViewController alloc] init];
    self.editController.delegate = self;
    [self dw_embedChild:self.editController inContainer:contentView];

    [self editProfileViewControllerDidUpdate:self.editController];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - DWEditProfileViewControllerDelegate

- (void)editProfileViewControllerDidUpdate:(DWEditProfileViewController *)controller {
    self.actionButton.enabled = controller.isValid;
}

#pragma mark - Actions

- (void)cancelButtonAction {
    [self.delegate editProfileViewControllerDidCancel:self];
}

- (void)actionButtonAction:(id)sender {
    [self.delegate editProfileViewController:self
                           updateDisplayName:self.editController.displayName
                                     aboutMe:self.editController.aboutMe
                             avatarURLString:self.editController.avatarURLString];
}
@end

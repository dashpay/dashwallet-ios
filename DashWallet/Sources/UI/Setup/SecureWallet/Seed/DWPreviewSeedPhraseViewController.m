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

#import "DWPreviewSeedPhraseViewController.h"

#import "DWPreviewSeedPhraseContentView.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWSeedPhraseModel.h"
#import "DWUIKit.h"
#import "DWVerifySeedPhraseViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPreviewSeedPhraseViewController () <DWPreviewSeedPhraseContentViewDelegate>

@property (nonatomic, strong) DWPreviewSeedPhraseModel *model;

@property (nonatomic, strong) DWPreviewSeedPhraseContentView *contentView;
@property (null_resettable, nonatomic, strong) UINotificationFeedbackGenerator *feedbackGenerator;

@end

@implementation DWPreviewSeedPhraseViewController

+ (instancetype)controllerWithModel:(DWPreviewSeedPhraseModel *)model {
    DWPreviewSeedPhraseViewController *controller = [[DWPreviewSeedPhraseViewController alloc] init];
    controller.model = model;

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
    [self setupContentViewModel];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.contentView viewWillAppear];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.contentView viewDidAppear];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.contentView.visibleSize = self.scrollView.bounds.size;
}

#pragma mark - Private

- (void)setupView {
    self.title = NSLocalizedString(@"Backup Wallet", nil);

    DWPreviewSeedPhraseContentView *contentView = [[DWPreviewSeedPhraseContentView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.delegate = self;
    [self.scrollView addSubview:contentView];
    self.contentView = contentView;

    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDidTakeScreenshotNotification:)
                                                 name:UIApplicationUserDidTakeScreenshotNotification
                                               object:nil];
}

- (void)setupContentViewModel {
    NSAssert(self.contentView, @"Configure content view first");

    DWSeedPhraseModel *seedPhrase = [self.model getOrCreateNewWallet];
    self.contentView.model = seedPhrase;
}

- (UINotificationFeedbackGenerator *)feedbackGenerator {
    if (!_feedbackGenerator) {
        _feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];
    }
    return _feedbackGenerator;
}

#pragma mark - Actions

- (void)continueButtonAction:(id)sender {
    DWSeedPhraseModel *seedPhrase = self.contentView.model;

    DWVerifySeedPhraseViewController *controller = [DWVerifySeedPhraseViewController
        controllerWithSeedPhrase:seedPhrase];
    controller.delegate = self.delegate;
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - DWPreviewSeedPhraseContentViewDelegate

- (void)previewSeedPhraseContentView:(DWPreviewSeedPhraseContentView *)view
               didChangeConfirmation:(BOOL)confirmed {
    self.continueButton.enabled = confirmed;
}

#pragma mark - Notifications

- (void)userDidTakeScreenshotNotification:(NSNotification *)notification {
    [self.feedbackGenerator prepare];

    NSString *title = NSLocalizedString(@"WARNING", nil);
    NSString *message = NSLocalizedString(@"Screenshots are visible to other apps and devices. Generate a new recovery phrase and keep it secret.", nil);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"OK", nil)
                  style:UIAlertActionStyleCancel
                handler:^(UIAlertAction *action) {
                    [self.model clearAllWallets];

                    [self.feedbackGenerator notificationOccurred:UINotificationFeedbackTypeError];

                    DWSeedPhraseModel *seedPhrase = [self.model getOrCreateNewWallet];
                    [self.contentView updateSeedPhraseModelAnimated:seedPhrase];
                    [self.contentView showScreenshotDetectedErrorMessage];

                    self.continueButton.enabled = NO;
                }];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

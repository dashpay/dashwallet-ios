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

#import "DWPreviewSeedPhraseViewController+DWProtected.h"

#import <DWAlertController/DWAlertController.h>

#import "DWPreviewSeedPhraseModel.h"
#import "DWScreenshotWarningViewController.h"
#import "DWSeedPhraseModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWPreviewSeedPhraseViewController

- (instancetype)initWithModel:(DWPreviewSeedPhraseModel *)model {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.model = model;
    }
    return self;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Done", nil);
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
    self.title = NSLocalizedString(@"Recovery Phrase", nil);
    self.actionButton.enabled = YES;

    DWPreviewSeedPhraseContentView *contentView = [[DWPreviewSeedPhraseContentView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.delegate = self;
    contentView.displayType = DWSeedPhraseDisplayType_Preview;
    [self.scrollView addSubview:contentView];
    self.contentView = contentView;

    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];

#if DEBUG
    UILongPressGestureRecognizer *gestureRecognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(debugContentViewLongPressAction:)];
    [contentView addGestureRecognizer:gestureRecognizer];
#endif /* DEBUG */

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

- (void)screenshotAlertOKAction {
    // NOP
}

#pragma mark - Actions

- (void)actionButtonAction:(id)sender {
    [self.delegate secureWalletRoutineDidCanceled:self];
}

#if DEBUG
- (void)debugContentViewLongPressAction:(UIGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) {
        return;
    }

    NSString *seed = [self.contentView.model debug_seedText];
    [UIPasteboard generalPasteboard].string = seed;
    NSLog(@"The seed phrase was copied to the clipboard.");
}
#endif /* DEBUG */

#pragma mark - DWPreviewSeedPhraseContentViewDelegate

- (void)previewSeedPhraseContentView:(DWPreviewSeedPhraseContentView *)view
               didChangeConfirmation:(BOOL)confirmed {
    self.actionButton.enabled = confirmed;
}

#pragma mark - Notifications

- (void)userDidTakeScreenshotNotification:(NSNotification *)notification {
    [self.feedbackGenerator prepare];

    DWScreenshotWarningViewController *warningController = [[DWScreenshotWarningViewController alloc] init];

    DWAlertController *alert = [DWAlertController alertControllerWithContentController:warningController];
    DWAlertAction *okAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:DWAlertActionStyleCancel
                                                     handler:^(DWAlertAction *_Nonnull action) {
                                                         [self screenshotAlertOKAction];
                                                     }];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

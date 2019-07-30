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

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};

#pragma mark - Helper

@protocol DWPreviewContinueButton <NSObject>

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

@end

@interface UIButton (DWPreviewContinueButton_UIButton) <DWPreviewContinueButton>
@end
@implementation UIButton (DWPreviewContinueButton_UIButton)
@end

@interface UIBarButtonItem (DWPreviewContinueButton_UIBarButtonItem) <DWPreviewContinueButton>
@end
@implementation UIBarButtonItem (DWPreviewContinueButton_UIBarButtonItem)
@end

#pragma mark - Controller

@interface DWPreviewSeedPhraseViewController () <DWPreviewSeedPhraseContentViewDelegate>

@property (nonatomic, strong) DWPreviewSeedPhraseModel *model;

@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property (strong, nonatomic) IBOutlet UIButton *continueButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@property (nonatomic, strong) DWPreviewSeedPhraseContentView *contentView;
@property (nullable, nonatomic, weak) id<DWPreviewContinueButton> previewContinueButton;
@property (null_resettable, nonatomic, strong) UINotificationFeedbackGenerator *feedbackGenerator;

@end

@implementation DWPreviewSeedPhraseViewController

+ (instancetype)controllerForNewWallet {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"PreviewSeedPhrase" bundle:nil];
    DWPreviewSeedPhraseViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWPreviewSeedPhraseModel alloc] init];

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
    [self.scrollView flashScrollIndicators];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.contentView.visibleSize = self.scrollView.bounds.size;
}

#pragma mark - Private

- (void)setupView {
    self.title = NSLocalizedString(@"Backup Wallet", nil);

    NSString *continueButtonTitle = NSLocalizedString(@"Continue", nil);
    if (IS_IPHONE_5_OR_LESS) {
        self.continueButton.hidden = YES;

        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:continueButtonTitle
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(continueButtonAction:)];
        self.navigationItem.rightBarButtonItem = barButtonItem;
        self.previewContinueButton = barButtonItem;
    }
    else {
        self.continueButton.hidden = NO;
        [self.continueButton setTitle:continueButtonTitle forState:UIControlStateNormal];
        self.previewContinueButton = self.continueButton;
    }
    self.previewContinueButton.enabled = NO;

    self.scrollView.scrollIndicatorInsets = SCROLL_INDICATOR_INSETS;


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

- (IBAction)continueButtonAction:(id)sender {
    DWSeedPhraseModel *seedPhrase = self.contentView.model;

    DWVerifySeedPhraseViewController *controller = [DWVerifySeedPhraseViewController
        controllerWithSeedPhrase:seedPhrase];
    controller.delegate = self.delegate;
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - DWPreviewSeedPhraseContentViewDelegate

- (void)previewSeedPhraseContentView:(DWPreviewSeedPhraseContentView *)view
               didChangeConfirmation:(BOOL)confirmed {
    self.previewContinueButton.enabled = confirmed;
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

                    self.previewContinueButton.enabled = NO;
                }];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Configuration

+ (CGFloat)deviceSpecificBottomPadding {
    if (IS_IPAD) { // All iPads including ones with home indicator
        return 24.0;
    }
    else if (DEVICE_HAS_HOME_INDICATOR) { // iPhone X-like, XS Max, X
        return 4.0;
    }
    else if (IS_IPHONE_6_PLUS) { // iPhone 6 Plus-like
        return 20.0;
    }
    else if (IS_IPHONE_6) { // iPhone 6-like
        return 16.0;
    }
    else { // iPhone 5-like
        return 0.0;
    }
}

@end

NS_ASSUME_NONNULL_END

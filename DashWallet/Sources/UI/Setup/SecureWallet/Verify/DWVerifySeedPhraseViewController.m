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

#import "DWVerifySeedPhraseViewController.h"

#import "DWUIKit.h"
#import "DWVerifiedSuccessfullyViewController.h"
#import "DWVerifySeedPhraseContentView.h"
#import "DWVerifySeedPhraseModel.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};

@interface DWVerifySeedPhraseViewController () <DWVerifySeedPhraseContentViewDelegate>

@property (nonatomic, strong) DWVerifySeedPhraseModel *model;

@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@property (nonatomic, strong) DWVerifySeedPhraseContentView *contentView;
@property (null_resettable, nonatomic, strong) UINotificationFeedbackGenerator *feedbackGenerator;

@end

@implementation DWVerifySeedPhraseViewController

+ (instancetype)controllerWithSeedPhrase:(DWSeedPhraseModel *)seedPhrase {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"VerifySeedPhrase" bundle:nil];
    DWVerifySeedPhraseViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWVerifySeedPhraseModel alloc] initWithSeedPhrase:seedPhrase];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.contentView viewDidAppear];
    [self.scrollView flashScrollIndicators];
    [self.feedbackGenerator prepare];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.contentView.visibleSize = self.scrollView.bounds.size;
}

#pragma mark - DWVerifySeedPhraseContentViewDelegate

- (void)verifySeedPhraseContentViewDidVerify:(DWVerifySeedPhraseContentView *)view {
    [self.delegate secureWalletRoutineDidVerify:self];
    [self.feedbackGenerator notificationOccurred:UINotificationFeedbackTypeSuccess];

    DWVerifiedSuccessfullyViewController *controller = [DWVerifiedSuccessfullyViewController controller];
    controller.delegate = self.delegate;
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - Private

- (void)setupView {
    self.title = NSLocalizedString(@"Backup Wallet", @"A noun. Used as a title.");

    self.scrollView.scrollIndicatorInsets = SCROLL_INDICATOR_INSETS;

    DWVerifySeedPhraseContentView *contentView = [[DWVerifySeedPhraseContentView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.model = self.model;
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
}

- (UINotificationFeedbackGenerator *)feedbackGenerator {
    if (!_feedbackGenerator) {
        _feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];
    }
    return _feedbackGenerator;
}

#pragma mark - Configuration

+ (CGFloat)deviceSpecificBottomPadding {
    if (IS_IPHONE_5_OR_LESS) {
        return 0.0;
    }
    else {
        return [super deviceSpecificBottomPadding];
    }
}

@end

NS_ASSUME_NONNULL_END

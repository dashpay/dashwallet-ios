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
#import "DWSeedPhraseControllerModel.h"
#import "DevicesCompatibility.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};

@interface DWPreviewSeedPhraseViewController ()

@property (nonatomic, strong) DWSeedPhraseControllerModel *model;

@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property (strong, nonatomic) IBOutlet UIButton *continueButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@property (nonatomic, strong) DWPreviewSeedPhraseContentView *contentView;

@end

@implementation DWPreviewSeedPhraseViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"PreviewSeedPhrase" bundle:nil];
    DWPreviewSeedPhraseViewController *controller = [storyboard instantiateInitialViewController];
    NSString *title = NSLocalizedString(@"Please write it down", nil);
    controller.model = [[DWSeedPhraseControllerModel alloc] initWithSubTitle:title];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

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
    }
    else {
        self.continueButton.hidden = NO;
        [self.continueButton setTitle:continueButtonTitle forState:UIControlStateNormal];
    }

    self.scrollView.scrollIndicatorInsets = SCROLL_INDICATOR_INSETS;

    DWPreviewSeedPhraseContentView *contentView = [[DWPreviewSeedPhraseContentView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.model = self.model;
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

#pragma mark - Actions

- (IBAction)continueButtonAction:(id)sender {
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

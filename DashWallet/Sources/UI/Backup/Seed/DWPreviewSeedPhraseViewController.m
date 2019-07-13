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

#import "DWSeedPhraseControllerModel.h"
#import "DWSeedPhraseTitledView.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const COMPACT_PADDING = 16.0;
static CGFloat const DEFAULT_PADDING = 64.0;
static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};

@interface DWPreviewSeedPhraseViewController ()

@property (nonatomic, strong) DWSeedPhraseControllerModel *model;

@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property (strong, nonatomic) IBOutlet UIButton *continueButton;

@property (nonatomic, strong) DWSeedPhraseTitledView *contentView;
@property (nonatomic, strong) NSLayoutConstraint *contentViewTopConstraint;

@end

@implementation DWPreviewSeedPhraseViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"PreviewSeedPhrase" bundle:nil];
    DWPreviewSeedPhraseViewController *controller = [storyboard instantiateInitialViewController];
    NSString *title = NSLocalizedString(@"Please write this down", nil);
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

    const CGFloat height = CGRectGetHeight(self.scrollView.bounds);
    const CGFloat contentHeight = self.contentView.intrinsicContentSize.height;
    CGFloat constant = 0.0;
    if (height - contentHeight >= DEFAULT_PADDING * 2.0) {
        constant = DEFAULT_PADDING;
    }
    else {
        constant = COMPACT_PADDING;
    }
    self.contentViewTopConstraint.constant = constant;
}

#pragma mark - Private

- (void)setupView {
    self.title = NSLocalizedString(@"Backup Wallet", nil);

    [self.continueButton setTitle:NSLocalizedString(@"Continue", nil)
                         forState:UIControlStateNormal];

    self.scrollView.scrollIndicatorInsets = SCROLL_INDICATOR_INSETS;

    DWSeedPhraseTitledView *contentView = [[DWSeedPhraseTitledView alloc] initWithType:DWSeedPhraseType_Preview];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.model = self.model;
    [self.scrollView addSubview:contentView];
    self.contentView = contentView;

    self.contentViewTopConstraint = [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor
                                                                          constant:COMPACT_PADDING];

    [NSLayoutConstraint activateConstraints:@[
        self.contentViewTopConstraint,
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];
}

@end

NS_ASSUME_NONNULL_END

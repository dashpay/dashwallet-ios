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

#import "DWVerifySeedPhraseContentView.h"
#import "DWVerifySeedPhraseModel.h"
#import "DevicesCompatibility.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};

@interface DWVerifySeedPhraseViewController () <DWVerifySeedPhraseContentViewDelegate>

@property (nonatomic, strong) DWVerifySeedPhraseModel *model;

@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@property (nonatomic, strong) DWVerifySeedPhraseContentView *contentView;

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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.contentView viewDidAppear];
    [self.scrollView flashScrollIndicators];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.contentView.visibleSize = self.scrollView.bounds.size;
}

#pragma mark - DWVerifySeedPhraseContentViewDelegate

- (void)verifySeedPhraseContentViewDidVerify:(DWVerifySeedPhraseContentView *)view {
    UIViewController *c = [UIViewController new];
    c.title = @"Verified Successfully";
    c.view.backgroundColor = [UIColor whiteColor];
    [self.navigationController pushViewController:c animated:YES];
}

#pragma mark - Private

- (void)setupView {
    self.title = NSLocalizedString(@"Backup Wallet", nil);

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

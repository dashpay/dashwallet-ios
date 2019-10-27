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

#import "DWBaseModalViewController.h"

#import "DWModalContentView.h"
#import "DWModalTransition.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const CORNER_RADIUS = 8.0;

@interface DWBaseModalViewController ()

@property (nonatomic, strong) DWModalTransition *modalTransition;
@property (nonatomic, strong) DWModalContentView *contentView;

@end

@implementation DWBaseModalViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _modalTransition = [[DWModalTransition alloc] init];

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupBaseModalView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.contentView setChevronViewFlattened:NO];
}

- (void)setModalTitle:(NSString *)title {
    self.contentView.title = title;
}

- (void)setupModalContentView:(UIView *)view {
    UIView *parentView = self.contentView.contentView;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [parentView addSubview:view];

    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:parentView.topAnchor],
        [view.leadingAnchor constraintEqualToAnchor:parentView.leadingAnchor],
        [view.bottomAnchor constraintEqualToAnchor:parentView.bottomAnchor],
        [view.trailingAnchor constraintEqualToAnchor:parentView.trailingAnchor],
    ]];
}

#pragma mark - DWModalInteractiveTransitionProgressHandler

- (void)interactiveTransitionDidUpdateProgress:(CGFloat)progress {
    const BOOL flattened = progress > 0.0 && progress < 1.0;
    [self.contentView setChevronViewFlattened:flattened];
}

#pragma mark - Private

- (void)setupBaseModalView {
    self.view.backgroundColor = [UIColor dw_backgroundColor];
    self.view.clipsToBounds = YES;
    self.view.layer.cornerRadius = CORNER_RADIUS;
    self.view.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;

    self.actionButton.enabled = YES;

    DWModalContentView *contentView = [[DWModalContentView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView setChevronViewFlattened:YES];
    self.contentView = contentView;

    [self setupContentView:contentView];
}

@end

NS_ASSUME_NONNULL_END

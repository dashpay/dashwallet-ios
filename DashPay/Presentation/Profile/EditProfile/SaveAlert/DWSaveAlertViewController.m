//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWSaveAlertViewController.h"

#import "DWModalPopupTransition.h"
#import "DWSaveAlertChildView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSaveAlertViewController () <DWSaveAlertChildViewDelegate>

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;

@end

NS_ASSUME_NONNULL_END

@implementation DWSaveAlertViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _modalTransition = [[DWModalPopupTransition alloc] initWithInteractiveTransitionAllowed:NO];

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.backgroundColor = [UIColor dw_backgroundColor];
    contentView.layer.cornerRadius = 8.0;
    contentView.layer.masksToBounds = YES;
    [self.view addSubview:contentView];

    DWSaveAlertChildView *childView = [[DWSaveAlertChildView alloc] init];
    childView.translatesAutoresizingMaskIntoConstraints = NO;
    childView.delegate = self;
    [contentView addSubview:childView];

    [NSLayoutConstraint activateConstraints:@[
        [contentView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [childView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                            constant:32.0],
        [childView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [childView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:childView.bottomAnchor
                                                 constant:32.0],
    ]];
}

#pragma mark - DWSaveAlertChildViewDelegate

- (void)saveAlertChildViewCancelAction:(DWSaveAlertChildView *)view {
    [self.delegate saveAlertViewControllerCancelAction:self];
}

- (void)saveAlertChildViewOKAction:(DWSaveAlertChildView *)view {
    [self.delegate saveAlertViewControllerOKAction:self];
}

@end

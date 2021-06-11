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

#import "DWSyncingAlertViewController.h"

#import "DWModalPopupTransition.h"
#import "DWSyncingAlertContentView.h"
#import "DWUIKit.h"


NS_ASSUME_NONNULL_BEGIN

@interface DWSyncingAlertViewController () <DWSyncingAlertContentViewDelegate>

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;
@property (null_resettable, nonatomic, strong) DWSyncingAlertContentView *childView;

@end

NS_ASSUME_NONNULL_END

@implementation DWSyncingAlertViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _modalTransition = [[DWModalPopupTransition alloc] init];

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;
    }
    return self;
}

- (id<DWSyncContainerProtocol>)model {
    return self.childView.model;
}

- (void)setModel:(id<DWSyncContainerProtocol>)model {
    self.childView.model = model;
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

    [contentView addSubview:self.childView];

    [NSLayoutConstraint activateConstraints:@[
        [contentView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.childView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:32.0],
        [self.childView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.childView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.childView.bottomAnchor
                                                 constant:32.0],
    ]];
}

#pragma mark - DWSyncingAlertContentViewDelegate

- (void)syncingAlertContentView:(DWSyncingAlertContentView *)view okButtonAction:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Private

- (DWSyncingAlertContentView *)childView {
    if (_childView == nil) {
        DWSyncingAlertContentView *childView = [[DWSyncingAlertContentView alloc] init];
        childView.translatesAutoresizingMaskIntoConstraints = NO;
        childView.delegate = self;
        _childView = childView;
    }
    return _childView;
}

@end

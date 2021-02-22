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

#import "DPAlertViewController.h"

#import "DPAlertChildContentsView.h"
#import "DWActionButton.h"
#import "DWModalPopupTransition.h"
#import "DWUIKit.h"

@interface DPAlertViewController ()

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;

@property (nullable, nonatomic, strong) UIImage *icon;
@property (nullable, nonatomic, strong) NSString *title_;
@property (nullable, nonatomic, strong) NSString *desc;

@end

@implementation DPAlertViewController

- (instancetype)initWithIcon:(UIImage *)icon
                       title:(NSString *)title
                 description:(NSString *)description {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _icon = icon;
        _title_ = title;
        _desc = description;

        _modalTransition = [[DWModalPopupTransition alloc] initWithInteractiveTransitionAllowed:YES];

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

    DPAlertChildContentsView *childView = [[DPAlertChildContentsView alloc] initWithFrame:CGRectZero];
    childView.translatesAutoresizingMaskIntoConstraints = NO;
    childView.icon = self.icon;
    childView.title = self.title_;
    childView.desc = self.desc;
    [contentView addSubview:childView];

    DWActionButton *okButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
    okButton.translatesAutoresizingMaskIntoConstraints = NO;
    okButton.usedOnDarkBackground = NO;
    okButton.small = YES;
    okButton.inverted = NO;
    [okButton setTitle:NSLocalizedString(@"OK", nil) forState:UIControlStateNormal];
    [okButton addTarget:self action:@selector(closeButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:okButton];

    [NSLayoutConstraint activateConstraints:@[
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [childView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                            constant:32.0],
        [childView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                constant:16.0],
        [contentView.trailingAnchor constraintEqualToAnchor:childView.trailingAnchor
                                                   constant:16.0],

        [okButton.topAnchor constraintEqualToAnchor:childView.bottomAnchor
                                           constant:32.0],
        [okButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:okButton.bottomAnchor
                                                 constant:20.0],
        [okButton.heightAnchor constraintGreaterThanOrEqualToConstant:40.0],
        [okButton.widthAnchor constraintEqualToAnchor:childView.widthAnchor
                                           multiplier:0.285],
    ]];
}

- (void)closeButtonAction:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

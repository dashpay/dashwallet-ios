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

#import "DWFullScreenModalControllerViewController.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWFullScreenModalControllerViewController ()

@property (readonly, nonatomic, strong) UIViewController *contentController;

@end

NS_ASSUME_NONNULL_END

@implementation DWFullScreenModalControllerViewController

- (instancetype)initWithController:(UIViewController *)controller {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _contentController = controller;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textColor = [UIColor dw_darkTitleColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
    label.text = self.title;
    label.adjustsFontForContentSizeCategory = YES;
    [header addSubview:label];

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton setImage:[[UIImage imageNamed:@"payments_nav_cross"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                  forState:UIControlStateNormal];
    cancelButton.tintColor = [UIColor dw_darkTitleColor];
    [cancelButton addTarget:self action:@selector(cancelButtonAction) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:cancelButton];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:contentView];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                             constant:8],
        [self.view.trailingAnchor constraintEqualToAnchor:header.trailingAnchor
                                                 constant:8],
        [header.heightAnchor constraintEqualToConstant:44],

        [contentView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

        [label.topAnchor constraintEqualToAnchor:header.topAnchor],
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor
                                            constant:44],
        [header.bottomAnchor constraintEqualToAnchor:label.bottomAnchor],

        [cancelButton.topAnchor constraintEqualToAnchor:header.topAnchor],
        [cancelButton.leadingAnchor constraintEqualToAnchor:label.trailingAnchor],
        [cancelButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [header.bottomAnchor constraintEqualToAnchor:cancelButton.bottomAnchor],
        [cancelButton.widthAnchor constraintEqualToConstant:44],
    ]];

    [self dw_embedChild:self.contentController inContainer:contentView];
}

- (void)cancelButtonAction {
    [self.delegate fullScreenModalControllerViewControllerDidCancel:self];
}

@end

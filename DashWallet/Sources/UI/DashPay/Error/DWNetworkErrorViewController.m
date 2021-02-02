//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWNetworkErrorViewController.h"

#import "DWModalPopupTransition.h"
#import "DWNetworkUnavailableView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNetworkErrorViewController ()

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;
@property (nonatomic, assign) DWErrorDescriptionType type;

@end

NS_ASSUME_NONNULL_END

@implementation DWNetworkErrorViewController

- (instancetype)initWithType:(DWErrorDescriptionType)type {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _type = type;

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

    DWNetworkUnavailableView *errorView = [[DWNetworkUnavailableView alloc] initWithFrame:CGRectZero];
    errorView.translatesAutoresizingMaskIntoConstraints = NO;
    switch (self.type) {
        case DWErrorDescriptionType_Profile:
            errorView.error = NSLocalizedString(@"Unable to fetch contact details", nil);
            break;
        case DWErrorDescriptionType_AcceptContactRequest:
            errorView.error = NSLocalizedString(@"Unable to accept contact request", nil);
            break;
        case DWErrorDescriptionType_SendContactRequest:
            errorView.error = NSLocalizedString(@"Unable to send contact request", nil);
            break;
    }
    [contentView addSubview:errorView];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setTitle:NSLocalizedString(@"Close", nil) forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:closeButton];


    [NSLayoutConstraint activateConstraints:@[
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [errorView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                            constant:32.0],
        [errorView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [errorView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],

        [closeButton.topAnchor constraintEqualToAnchor:errorView.bottomAnchor
                                              constant:32.0],
        [closeButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:closeButton.bottomAnchor
                                                 constant:16.0],
        [closeButton.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
    ]];
}

- (void)closeButtonAction:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

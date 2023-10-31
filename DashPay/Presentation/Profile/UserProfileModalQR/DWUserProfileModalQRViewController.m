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

#import "DWUserProfileModalQRViewController.h"

#import "DWModalPopupTransition.h"
#import "DWUIKit.h"
#import "DWUserProfileModalQRContentView.h"
#import "UIViewController+DWShareReceiveInfo.h"

static CGFloat const CORNER_RADIUS = 8.0;

static CGFloat VerticalPadding(void) {
    if (IS_IPAD) {
        return 32.0;
    }
    else if (IS_IPHONE_6 || IS_IPHONE_5_OR_LESS) {
        return 16.0;
    }
    else {
        return 24.0;
    }
}

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileModalQRViewController () <DWUserProfileModalQRContentViewDelegate>

@property (readonly, nonatomic, strong) id<DWReceiveModelProtocol> model;

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileModalQRViewController

- (instancetype)initWithModel:(id<DWReceiveModelProtocol>)model {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = model;

        _modalTransition = [[DWModalPopupTransition alloc] init];

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];
    self.view.clipsToBounds = YES;
    self.view.layer.cornerRadius = CORNER_RADIUS;

    UIView *contentView = self.view;

    DWUserProfileModalQRContentView *childView = [[DWUserProfileModalQRContentView alloc] initWithModel:self.model];
    childView.translatesAutoresizingMaskIntoConstraints = NO;
    childView.delegate = self;
    [contentView addSubview:childView];

    const CGFloat padding = VerticalPadding();
    [NSLayoutConstraint activateConstraints:@[
        [childView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [childView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [childView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [childView.topAnchor constraintGreaterThanOrEqualToAnchor:contentView.topAnchor
                                                         constant:padding],
        [childView.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentView.bottomAnchor
                                                            constant:-padding],
    ]];
}

#pragma mark - DWUserProfileModalQRContentViewDelegate

- (void)userProfileModalQRContentView:(DWUserProfileModalQRContentView *)view closeButtonAction:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)userProfileModalQRContentView:(DWUserProfileModalQRContentView *)view shareButtonAction:(UIButton *)sender {
    [self dw_shareReceiveInfo:self.model sender:sender];
}

@end

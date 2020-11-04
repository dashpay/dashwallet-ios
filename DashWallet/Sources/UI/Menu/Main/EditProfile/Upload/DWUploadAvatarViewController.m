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

#import "DWUploadAvatarViewController.h"

#import "DWModalPopupTransition.h"
#import "DWUIKit.h"
#import "DWUploadAvatarChildView.h"
#import "DWUploadAvatarModel.h"

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

@interface DWUploadAvatarViewController () <DWUploadAvatarChildViewDelegate>

@property (nonatomic, strong) DWUploadAvatarModel *model;
@property (nonatomic, strong) DWModalPopupTransition *modalTransition;

@end

NS_ASSUME_NONNULL_END

@implementation DWUploadAvatarViewController

- (instancetype)initWithImage:(UIImage *)image {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = [[DWUploadAvatarModel alloc] initWithImage:image];
        _modalTransition = [[DWModalPopupTransition alloc] initWithInteractiveTransitionAllowed:NO];

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;
    }
    return self;
}

- (UIImage *)image {
    return self.model.image;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];

    UIView *contentView = self.view;

    DWUploadAvatarChildView *childView = [[DWUploadAvatarChildView alloc] initWithFrame:CGRectZero];
    childView.model = self.model;
    childView.delegate = self;
    childView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:childView];

    const CGFloat padding = VerticalPadding();
    [NSLayoutConstraint activateConstraints:@[
        [childView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [childView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [childView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [childView.heightAnchor constraintEqualToAnchor:childView.widthAnchor],
    ]];
}

#pragma mark - DWUploadAvatarChildViewDelegate

- (void)uploadAvatarChildViewDidFinish:(DWUploadAvatarChildView *)view {
    [self.delegate uploadAvatarViewController:self didFinishWithURLString:self.model.resultURLString];
}

- (void)uploadAvatarChildViewDidCancel:(DWUploadAvatarChildView *)view {
    [self.delegate uploadAvatarViewControllerDidCancel:self];
}

@end

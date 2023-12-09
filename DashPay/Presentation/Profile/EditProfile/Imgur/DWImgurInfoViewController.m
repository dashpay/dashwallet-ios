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

#import "DWImgurInfoViewController.h"

#import "DWImgurInfoChildView.h"
#import "DWModalPopupTransition.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWImgurInfoViewController () <DWImgurInfoChildViewDelegate>

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;

@end

NS_ASSUME_NONNULL_END

@implementation DWImgurInfoViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _modalTransition = [[DWModalPopupTransition alloc] initWithInteractiveTransitionAllowed:YES];

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    DWImgurInfoChildView *childView = [[DWImgurInfoChildView alloc] init];
    childView.translatesAutoresizingMaskIntoConstraints = NO;
    childView.delegate = self;
    [self.view addSubview:childView];

    [NSLayoutConstraint activateConstraints:@[
        [childView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [childView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [childView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

#pragma mark DWImgurInfoChildViewDelegate

- (void)imgurInfoChildViewAcceptAction:(DWImgurInfoChildView *)view {
    [self.delegate imgurInfoViewControllerDidAccept:self];
}

- (void)imgurInfoChildViewCancelAction:(DWImgurInfoChildView *)view {
    [self.delegate imgurInfoViewControllerDidCancel:self];
}

@end

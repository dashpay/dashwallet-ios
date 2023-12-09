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

#import "DWInfoPopupViewController.h"

#import "DWInfoPopupContentView.h"

@interface DWInfoPopupViewController ()

@property (readonly, nonatomic, copy) NSString *text;
@property (readonly, nonatomic, assign) CGPoint offset;

@property (nonatomic, strong) DWInfoPopupContentView *contentView;

@end

@implementation DWInfoPopupViewController

- (instancetype)initWithText:(NSString *)text offset:(CGPoint)offset {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _text = text;
        _offset = offset;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];

    DWInfoPopupContentView *contentView = [[DWInfoPopupContentView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.text = self.text;
    contentView.pointerOffset = self.offset;
    [self.view addSubview:contentView];
    self.contentView = contentView;

    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapAction)];
    [self.view addGestureRecognizer:tapRecognizer];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)tapAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

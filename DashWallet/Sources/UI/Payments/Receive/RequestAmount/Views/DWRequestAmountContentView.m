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

#import "DWRequestAmountContentView.h"

#import "DWReceiveModelProtocol.h"
#import "DWUIKit.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWRequestAmountContentView ()

@property (nonatomic, strong) id<DWReceiveModelProtocol> model;
@property (nonatomic, strong) DWAmountPreviewView *amountView;
@property (nonatomic, strong) DWReceiveContentView *contentView;

@end

@implementation DWRequestAmountContentView

- (instancetype)initWithModel:(id<DWReceiveModelProtocol>)model {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _model = model;

        self.backgroundColor = [UIColor dw_backgroundColor];

        DWAmountPreviewView *amountView = [[DWAmountPreviewView alloc] initWithFrame:CGRectZero];
        amountView.translatesAutoresizingMaskIntoConstraints = NO;
        [amountView setAmount:model.amount];
        [self addSubview:amountView];
        _amountView = amountView;


        DWReceiveContentView *contentView = [DWReceiveContentView viewWith:model];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        __weak typeof(self) weakSelf = self;

        contentView.shareHandler = ^(UIButton *sender) {
            [weakSelf.delegate requestAmountContentView:weakSelf shareButtonAction:sender];
        };

        [contentView setSpecifyAmountButtonHidden:YES];
        [self addSubview:contentView];
        _contentView = contentView;

        [NSLayoutConstraint activateConstraints:@[
            [amountView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [amountView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [amountView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [contentView.topAnchor constraintEqualToAnchor:amountView.bottomAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END

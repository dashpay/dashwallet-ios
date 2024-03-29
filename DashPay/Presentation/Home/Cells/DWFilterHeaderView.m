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

#import "DWFilterHeaderView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWFilterHeaderView ()

@property (weak, nonatomic) IBOutlet UIView *contentView;

@property (strong, nonatomic) NSLayoutConstraint *leadingContentConstraint;
@property (strong, nonatomic) NSLayoutConstraint *trailingContentConstraint;
@property (strong, nonatomic) NSLayoutConstraint *widthContentConstraint;

@end

@implementation DWFilterHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil];
    [self addSubview:self.contentView];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
        (self.leadingContentConstraint = [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor]),
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        (self.trailingContentConstraint = [self.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor]),
        (self.widthContentConstraint = [self.contentView.widthAnchor constraintEqualToAnchor:self.widthAnchor]),
    ]];

    self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
    self.filterButton.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];

    [self.infoButton setHidden:YES];
}

- (void)setPadding:(CGFloat)padding {
    _padding = padding;

    self.leadingContentConstraint.constant = padding;
    self.trailingContentConstraint.constant = padding;
    self.widthContentConstraint.constant = -padding * 2;
}

- (IBAction)filterButtonAction:(UIButton *)sender {
    [self.delegate filterHeaderView:self filterButtonAction:sender];
}

- (IBAction)infoButtonAction:(UIButton *)sender {
    [self.delegate filterHeaderView:self infoButtonAction:sender];
}

@end

NS_ASSUME_NONNULL_END

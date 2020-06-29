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

#import "DWDPAmountContactView.h"

#import "DWDPSmallContactView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const SEPARATOR = 1.0;

@interface DWDPAmountContactView ()

@property (readonly, nonatomic, strong) CALayer *separatorLayer;
@property (readonly, nonatomic, strong) DWDPSmallContactView *contactView;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPAmountContactView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup_amountContactView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup_amountContactView];
    }
    return self;
}

- (id<DWDPBasicItem>)item {
    return self.contactView.item;
}

- (void)setItem:(id<DWDPBasicItem>)item {
    self.contactView.item = item;
}

- (void)setup_amountContactView {
    self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    CALayer *separatorLayer = [CALayer layer];
    separatorLayer.backgroundColor = [UIColor dw_separatorLineColor].CGColor;
    [self.layer addSublayer:separatorLayer];
    _separatorLayer = separatorLayer;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.5;
    titleLabel.numberOfLines = 0;
    titleLabel.textColor = [UIColor dw_quaternaryTextColor];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.text = NSLocalizedString(@"Sending to", nil);
    [self addSubview:titleLabel];

    DWDPSmallContactView *contactView = [[DWDPSmallContactView alloc] initWithFrame:CGRectZero];
    contactView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:contactView];
    _contactView = contactView;

    //    [titleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow - 2 forAxis:UILayoutConstraintAxisHorizontal];
    //    [contactView setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [contactView setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                 forAxis:UILayoutConstraintAxisHorizontal];

    //    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ titleLabel, contactView ]];
    //    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    //    stackView.axis = UILayoutConstraintAxisHorizontal;
    //    stackView.alignment = UIStackViewAlignmentCenter;
    //    stackView.spacing = 16.0;
    //    [self addSubview:stackView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],

        [contactView.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor
                                                               constant:16.0],
        [contactView.topAnchor constraintEqualToAnchor:self.topAnchor
                                              constant:10.0],
        [self.bottomAnchor constraintEqualToAnchor:contactView.bottomAnchor
                                          constant:10.0],
        [self.trailingAnchor constraintEqualToAnchor:contactView.trailingAnchor],

        //        [stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        //        [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        //        [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        //        [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [titleLabel.widthAnchor constraintGreaterThanOrEqualToAnchor:self.widthAnchor
                                                          multiplier:0.35],
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGSize size = self.bounds.size;
    self.separatorLayer.frame = CGRectMake(0.0, 0, size.width, SEPARATOR);
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    self.separatorLayer.backgroundColor = [UIColor dw_separatorLineColor].CGColor;
}

@end

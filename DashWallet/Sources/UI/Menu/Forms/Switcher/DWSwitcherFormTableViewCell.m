//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWSwitcherFormTableViewCell.h"

#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSwitcherFormTableViewCell ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UISwitch *switcher;

@end

@implementation DWSwitcherFormTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        UIView *contentView = self.roundedContentView;
        NSParameterAssert(contentView);

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = [UIColor dw_backgroundColor];
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.numberOfLines = 0;
        titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.minimumScaleFactor = 0.5;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];
        [contentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        UISwitch *switcher = [[UISwitch alloc] initWithFrame:CGRectZero];
        switcher.translatesAutoresizingMaskIntoConstraints = NO;
        switcher.onTintColor = [UIColor dw_dashBlueColor];
        switcher.transform = CGAffineTransformMakeScale(0.705, 0.705);
        [switcher addTarget:self action:@selector(switcherAction:) forControlEvents:UIControlEventValueChanged];
        [contentView addSubview:switcher];
        _switcher = switcher;

        const CGFloat margin = DWDefaultMargin();
        const CGFloat padding = DW_FORM_CELL_VERTICAL_PADDING;

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:padding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                     constant:margin],
            [titleLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                    constant:-padding],

            [switcher.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                   constant:DW_FORM_CELL_SPACING],
            [switcher.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                    constant:-margin],
            [switcher.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        ]];

        [self setupObserving];
    }

    return self;
}

- (void)setupObserving {
    [self mvvm_observe:DW_KEYPATH(self, cellModel.title)
                  with:^(__typeof(self) self, NSString *value) {
                      self.titleLabel.text = value ?: @" ";
                  }];

    [self mvvm_observe:DW_KEYPATH(self, cellModel.on)
                  with:^(__typeof(self) self, NSNumber *value) {
                      const BOOL animated = self.window != nil;
                      const BOOL on = value.boolValue;
                      if (self.switcher.isOn != on) {
                          [self.switcher setOn:on animated:animated];
                      }
                  }];
}

- (BOOL)shouldAnimatePressWhenHighlighted {
    return NO;
}

#pragma mark - Private

- (void)switcherAction:(UISwitch *)sender {
    self.cellModel.on = sender.on;

    if (self.cellModel.didChangeValueBlock) {
        self.cellModel.didChangeValueBlock(self.cellModel);
    }
}

@end

NS_ASSUME_NONNULL_END

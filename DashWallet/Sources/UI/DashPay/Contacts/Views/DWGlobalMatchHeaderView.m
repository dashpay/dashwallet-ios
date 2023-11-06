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

#import "DWGlobalMatchHeaderView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWGlobalMatchHeaderView ()

@property (nonatomic, strong) UILabel *descriptionLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWGlobalMatchHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.backgroundColor = [UIColor dw_backgroundColor];
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        label.textColor = [UIColor dw_darkTitleColor];
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        [self addSubview:label];
        _descriptionLabel = label;

        UILayoutGuide *guide = self.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:self.topAnchor
                                            constant:32.0],
            [label.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:label.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:label.bottomAnchor
                                              constant:32.0],
        ]];
    }
    return self;
}

- (void)setSearchQuery:(NSString *)searchQuery {
    if (_searchQuery == nil || ![_searchQuery isEqualToString:searchQuery]) {
        self.isContentChanged = YES;
    }

    _searchQuery = searchQuery;

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];

    NSAttributedString *title = [[NSAttributedString alloc]
        initWithString:NSLocalizedString(@"More Suggestions", nil)
            attributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3]}];
    [result appendAttributedString:title];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n"]];

    NSString *format = NSLocalizedString(@"Users that matches %@ who are currently not in your contacts", nil);
    NSString *query = [NSString stringWithFormat:@"\"%@\"", searchQuery ?: @""];
    NSString *text = [NSString stringWithFormat:format, query];

    NSMutableAttributedString *attributed =
        [[NSMutableAttributedString alloc] initWithString:text
                                               attributes:@{NSFontAttributeName : self.regularFont}];

    NSRange queryRange = [text rangeOfString:query];
    if (queryRange.location != NSNotFound) {
        [attributed removeAttribute:NSFontAttributeName range:queryRange];
        [attributed setAttributes:@{NSFontAttributeName : self.boldFont} range:queryRange];
    }

    [result appendAttributedString:attributed];

    [result endEditing];

    self.descriptionLabel.attributedText = result;
}

- (UIFont *)regularFont {
    return [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
}

- (UIFont *)boldFont {
    return [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
}

@end

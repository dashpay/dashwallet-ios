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

#import "DWContactsSearchPlaceholderView.h"

#import "DWActionButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsSearchPlaceholderView ()

@property (nonatomic, strong) UILabel *descriptionLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsSearchPlaceholderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        label.textColor = [UIColor dw_darkTitleColor];
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
        _descriptionLabel = label;

        DWActionButton *button = [[DWActionButton alloc] initWithFrame:CGRectZero];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.small = YES;
        button.inverted = YES;
        button.usedOnDarkBackground = NO;
        button.imageEdgeInsets = UIEdgeInsetsMake(0.0, -8.0, 0.0, 0.0);
        [button setImage:[UIImage imageNamed:@"dp_search_add_contact"] forState:UIControlStateNormal];
        [button setTitle:NSLocalizedString(@"Search for a User on the Dash Network", nil)
                forState:UIControlStateNormal];
        [button addTarget:self action:@selector(actionButtonAction:) forControlEvents:UIControlEventTouchUpInside];

        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        NSArray<UIView *> *views = @[ label, button ];
        UIStackView *verticalStackView = [[UIStackView alloc] initWithArrangedSubviews:views];
        verticalStackView.translatesAutoresizingMaskIntoConstraints = NO;
        verticalStackView.axis = UILayoutConstraintAxisVertical;
        verticalStackView.alignment = UIStackViewAlignmentCenter;
        verticalStackView.spacing = 24.0;
        [self addSubview:verticalStackView];

        UILayoutGuide *guide = self.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [verticalStackView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                        constant:32.0],
            [verticalStackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:verticalStackView.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:verticalStackView.bottomAnchor
                                              constant:16.0],
            [button.heightAnchor constraintEqualToConstant:44.0],
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

    NSString *format = NSLocalizedString(@"There are no users that match with the name %@ in your contacts", nil);
    NSString *query = [NSString stringWithFormat:@"\"%@\"", searchQuery ?: @""];
    NSString *text = [NSString stringWithFormat:format, query];

    NSAttributedString *attributed =
        [[NSAttributedString alloc] initWithString:text
                                        attributes:@{NSFontAttributeName : self.regularFont}];
    [result appendAttributedString:attributed];

    NSRange queryRange = [text rangeOfString:query];
    if (queryRange.location != NSNotFound) {
        [result removeAttribute:NSFontAttributeName range:queryRange];
        [result setAttributes:@{NSFontAttributeName : self.boldFont} range:queryRange];
    }

    [result endEditing];

    self.descriptionLabel.attributedText = result;
}

- (void)actionButtonAction:(UIButton *)sender {
    [self.delegate contactsSearchPlaceholderView:self searchAction:sender];
}

- (UIFont *)regularFont {
    return [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
}

- (UIFont *)boldFont {
    return [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
}

@end

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

#import "DWUserSearchStateViewController.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWUserSearchState) {
    DWUserSearchState_Placeholder,
    DWUserSearchState_Searching,
    DWUserSearchState_NoResults,
    DWUserSearchState_Error,
};


@interface DWUserSearchStateViewController ()

@property (null_resettable, nonatomic, strong) UIImageView *iconImageView;
@property (null_resettable, nonatomic, strong) UILabel *descriptionLabel;

@property (nonatomic, assign) DWUserSearchState state;
@property (nullable, copy, nonatomic) NSString *searchQuery;
@property (nullable, nonatomic, strong) NSError *error;


@end

NS_ASSUME_NONNULL_END

@implementation DWUserSearchStateViewController

- (void)setPlaceholderState {
    self.searchQuery = nil;
    self.error = nil;
    self.state = DWUserSearchState_Placeholder;

    [self reloadData];
}

- (void)setSearchingStateWithQuery:(NSString *)query {
    self.searchQuery = query;
    self.error = nil;
    self.state = DWUserSearchState_Searching;

    [self reloadData];
}

- (void)setNoResultsStateWithQuery:(NSString *)query {
    self.searchQuery = query;
    self.error = nil;
    self.state = DWUserSearchState_NoResults;

    [self reloadData];
}

- (void)setErrorStateWithError:(NSError *)error {
    self.searchQuery = nil;
    self.error = error;
    self.state = DWUserSearchState_Error;

    [self reloadData];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    NSArray<UIView *> *views = @[ self.iconImageView, self.descriptionLabel ];
    UIStackView *verticalStackView = [[UIStackView alloc] initWithArrangedSubviews:views];
    verticalStackView.translatesAutoresizingMaskIntoConstraints = NO;
    verticalStackView.axis = UILayoutConstraintAxisVertical;
    verticalStackView.alignment = UIStackViewAlignmentCenter;
    [verticalStackView setCustomSpacing:24.0 afterView:self.iconImageView];

    UIStackView *horizontalStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ verticalStackView ]];
    horizontalStackView.translatesAutoresizingMaskIntoConstraints = NO;
    horizontalStackView.axis = UILayoutConstraintAxisHorizontal;
    horizontalStackView.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:horizontalStackView];

    UILayoutGuide *guide = self.view.layoutMarginsGuide;

    [NSLayoutConstraint activateConstraints:@[
        [horizontalStackView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [horizontalStackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [guide.trailingAnchor constraintEqualToAnchor:horizontalStackView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:horizontalStackView.bottomAnchor],
    ]];

    [self reloadData];
}

- (UIImageView *)iconImageView {
    if (_iconImageView == nil) {
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        _iconImageView = imageView;
    }
    return _iconImageView;
}

- (UILabel *)descriptionLabel {
    if (_descriptionLabel == nil) {
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
    }
    return _descriptionLabel;
}

- (void)reloadData {
    UIFont *boldFont = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
    UIFont *regularFont = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];

    switch (self.state) {
        case DWUserSearchState_Placeholder: {
            self.iconImageView.image = [UIImage imageNamed:@"dp_user_search_placeholder"];

            NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
            [result beginEditing];

            NSAttributedString *title =
                [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Add a New Contact", nil)
                                                attributes:@{NSFontAttributeName : boldFont}];
            [result appendAttributedString:title];

            [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];

            NSAttributedString *subtitle =
                [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Find a user on the Dash Network", nil)
                                                attributes:@{NSFontAttributeName : regularFont}];
            [result appendAttributedString:subtitle];

            [result endEditing];

            self.descriptionLabel.attributedText = result;

            break;
        }
        case DWUserSearchState_Searching: {
            NSParameterAssert(self.searchQuery);

            // TODO: fix icon
            self.iconImageView.image = [UIImage imageNamed:@"dp_user_search_placeholder"];

            NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
            [result beginEditing];

            NSString *format = NSLocalizedString(@"Searching for username %@ on the Dash Network", nil);
            NSString *query = [NSString stringWithFormat:@"\"%@\"", self.searchQuery ?: @""];
            NSString *text = [NSString stringWithFormat:format, query];

            NSAttributedString *attributed =
                [[NSAttributedString alloc] initWithString:text
                                                attributes:@{NSFontAttributeName : regularFont}];
            [result appendAttributedString:attributed];

            NSRange queryRange = [text rangeOfString:query];
            if (queryRange.location != NSNotFound) {
                [result removeAttribute:NSFontAttributeName range:queryRange];
                [result setAttributes:@{NSFontAttributeName : boldFont} range:queryRange];
            }

            [result endEditing];

            self.descriptionLabel.attributedText = result;

            break;
        }
        case DWUserSearchState_NoResults: {
            NSParameterAssert(self.searchQuery);

            self.iconImageView.image = [UIImage imageNamed:@"dp_user_search_warning"];

            NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
            [result beginEditing];

            NSString *format = NSLocalizedString(@"There are no users that matches with the name %@", nil);
            NSString *query = [NSString stringWithFormat:@"\"%@\"", self.searchQuery ?: @""];
            NSString *text = [NSString stringWithFormat:format, query];

            NSAttributedString *attributed =
                [[NSAttributedString alloc] initWithString:text
                                                attributes:@{NSFontAttributeName : regularFont}];
            [result appendAttributedString:attributed];

            NSRange queryRange = [text rangeOfString:query];
            if (queryRange.location != NSNotFound) {
                [result removeAttribute:NSFontAttributeName range:queryRange];
                [result setAttributes:@{NSFontAttributeName : boldFont} range:queryRange];
            }

            [result endEditing];

            self.descriptionLabel.attributedText = result;

            break;
        }
        case DWUserSearchState_Error: {
            self.iconImageView.image = [UIImage imageNamed:@"dp_user_search_warning"];

            NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
            [result beginEditing];

            NSAttributedString *title =
                [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Error", nil)
                                                attributes:@{NSFontAttributeName : boldFont}];
            [result appendAttributedString:title];

            if (self.error) {
                [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];

                NSAttributedString *subtitle =
                    [[NSAttributedString alloc] initWithString:self.error.localizedDescription
                                                    attributes:@{NSFontAttributeName : regularFont}];
                [result appendAttributedString:subtitle];
            }

            [result endEditing];

            self.descriptionLabel.attributedText = result;

            break;
        }
    }
}

@end

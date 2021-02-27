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

#import "DWSearchStateViewController.h"

#import "DWActionButton.h"
#import "DWInvitationSuggestionView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWUserSearchState) {
    DWUserSearchState_PlaceholderGlobal,
    DWUserSearchState_PlaceholderLocal,
    DWUserSearchState_Searching,
    DWUserSearchState_NoResultsGlobal,
    DWUserSearchState_NoResultsLocal,
    DWUserSearchState_Error,
};


@interface DWSearchStateViewController ()

@property (null_resettable, nonatomic, strong) UIImageView *iconImageView;
@property (null_resettable, nonatomic, strong) UILabel *descriptionLabel;
@property (null_resettable, nonatomic, strong) UIButton *actionButton;
@property (null_resettable, nonatomic, strong) DWInvitationSuggestionView *invitationView;

@property (nonatomic, assign) DWUserSearchState state;
@property (nullable, copy, nonatomic) NSString *searchQuery;

@end

NS_ASSUME_NONNULL_END

@implementation DWSearchStateViewController

- (void)setPlaceholderGlobalState {
    self.searchQuery = nil;
    self.state = DWUserSearchState_PlaceholderGlobal;

    [self reloadData];
}

- (void)setPlaceholderLocalState {
    self.searchQuery = nil;
    self.state = DWUserSearchState_PlaceholderLocal;

    [self reloadData];
}

- (void)setSearchingStateWithQuery:(NSString *)query {
    self.searchQuery = query;
    self.state = DWUserSearchState_Searching;

    [self reloadData];
}

- (void)setNoResultsGlobalStateWithQuery:(NSString *)query {
    self.searchQuery = query;
    self.state = DWUserSearchState_NoResultsGlobal;

    [self reloadData];
}

- (void)setNoResultsLocalStateWithQuery:(NSString *)query {
    self.searchQuery = query;
    self.state = DWUserSearchState_NoResultsLocal;

    [self reloadData];
}

- (void)setErrorState {
    self.searchQuery = nil;
    self.state = DWUserSearchState_Error;

    [self reloadData];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    NSArray<UIView *> *views = @[ self.iconImageView, self.descriptionLabel, self.actionButton ];
    UIStackView *verticalStackView = [[UIStackView alloc] initWithArrangedSubviews:views];
    verticalStackView.translatesAutoresizingMaskIntoConstraints = NO;
    verticalStackView.axis = UILayoutConstraintAxisVertical;
    verticalStackView.alignment = UIStackViewAlignmentCenter;
    verticalStackView.spacing = 24.0;

    UIStackView *horizontalStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ verticalStackView ]];
    horizontalStackView.translatesAutoresizingMaskIntoConstraints = NO;
    horizontalStackView.axis = UILayoutConstraintAxisHorizontal;
    horizontalStackView.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:horizontalStackView];

    [self.view addSubview:self.invitationView];

    UILayoutGuide *guide = self.view.layoutMarginsGuide;

    [NSLayoutConstraint activateConstraints:@[
        [horizontalStackView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [horizontalStackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [guide.trailingAnchor constraintEqualToAnchor:horizontalStackView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:horizontalStackView.bottomAnchor],
        [self.actionButton.heightAnchor constraintEqualToConstant:44.0],

        [self.invitationView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [guide.trailingAnchor constraintEqualToAnchor:self.invitationView.trailingAnchor],
        [guide.bottomAnchor constraintEqualToAnchor:self.invitationView.bottomAnchor],
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

- (UIButton *)actionButton {
    if (_actionButton == nil) {
        DWActionButton *button = [[DWActionButton alloc] initWithFrame:CGRectZero];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.small = YES;
        button.inverted = YES;
        button.usedOnDarkBackground = NO;
        [button addTarget:self action:@selector(actionButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        _actionButton = button;
    }
    return _actionButton;
}

- (DWInvitationSuggestionView *)invitationView {
    if (!_invitationView) {
        _invitationView = [[DWInvitationSuggestionView alloc] init];
        _invitationView.translatesAutoresizingMaskIntoConstraints = NO;
        [_invitationView.inviteButton addTarget:self
                                         action:@selector(inviteButtonAction:)
                               forControlEvents:UIControlEventTouchUpInside];
    }
    return _invitationView;
}

- (void)reloadData {
    switch (self.state) {
        case DWUserSearchState_PlaceholderGlobal: {
            [self configurePlaceholderState];

            break;
        }
        case DWUserSearchState_PlaceholderLocal: {
            [self configurePlaceholderState];
            [self configureActionButtonForSearchUsers];

            break;
        }
        case DWUserSearchState_Searching: {
            [self configureSearchingAnimationState];

            break;
        }
        case DWUserSearchState_NoResultsGlobal: {
            [self configureNoResultsGlobalState];

            break;
        }
        case DWUserSearchState_NoResultsLocal: {
            [self configureNoResultsLocalState];
            [self configureActionButtonForSearchUsers];

            break;
        }
        case DWUserSearchState_Error: {
            [self configureSearchErrorState];

            break;
        }
    }
}

- (void)actionButtonAction:(UIButton *)sender {
    [self.delegate searchStateViewController:self buttonAction:sender];
}

- (void)inviteButtonAction:(UIButton *)sender {
    [self.delegate searchStateViewController:self inviteButtonAction:sender];
}

- (void)configurePlaceholderState {
    self.invitationView.hidden = YES;
    self.actionButton.hidden = YES;

    [self.iconImageView stopAnimating];
    self.iconImageView.animationImages = nil;
    self.iconImageView.image = [UIImage imageNamed:@"dp_user_search_placeholder"];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];

    NSAttributedString *title =
        [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Add a New Contact", nil)
                                        attributes:@{NSFontAttributeName : self.boldFont}];
    [result appendAttributedString:title];

    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];

    NSAttributedString *subtitle =
        [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Find a user on the Dash Network", nil)
                                        attributes:@{NSFontAttributeName : self.regularFont}];
    [result appendAttributedString:subtitle];

    [result endEditing];

    self.descriptionLabel.attributedText = result;
}

- (void)configureSearchingAnimationState {
    NSParameterAssert(self.searchQuery);

    self.invitationView.hidden = YES;
    self.actionButton.hidden = YES;

    if (self.iconImageView.animationImages == nil) {
        NSArray<UIImage *> *frames = @[
            [UIImage imageNamed:@"dp_user_search_anim_1"],
            [UIImage imageNamed:@"dp_user_search_anim_2"],
            [UIImage imageNamed:@"dp_user_search_anim_3"],
            [UIImage imageNamed:@"dp_user_search_anim_4"],
        ];
        self.iconImageView.animationImages = frames;
        self.iconImageView.animationDuration = 0.65;
        self.iconImageView.animationRepeatCount = 0;
        [self.iconImageView startAnimating];
    }

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];

    NSString *format = NSLocalizedString(@"Searching for username %@ on the Dash Network", nil);
    NSString *query = [NSString stringWithFormat:@"\"%@\"", self.searchQuery ?: @""];
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

- (void)configureNoResultsGlobalState {
    NSParameterAssert(self.searchQuery);

    self.invitationView.hidden = NO;
    self.actionButton.hidden = YES;

    [self.iconImageView stopAnimating];
    self.iconImageView.animationImages = nil;
    self.iconImageView.image = [UIImage imageNamed:@"dp_user_search_warning"];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];

    NSString *format = NSLocalizedString(@"There are no users that match with the name %@", nil);
    NSString *query = [NSString stringWithFormat:@"\"%@\"", self.searchQuery ?: @""];
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

- (void)configureNoResultsLocalState {
    NSParameterAssert(self.searchQuery);

    self.invitationView.hidden = YES;
    self.actionButton.hidden = YES;

    [self.iconImageView stopAnimating];
    self.iconImageView.animationImages = nil;
    self.iconImageView.image = [UIImage imageNamed:@"dp_user_search_warning"];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];

    NSString *format = NSLocalizedString(@"There are no users that match with the name %@ in your contacts", nil);
    NSString *query = [NSString stringWithFormat:@"\"%@\"", self.searchQuery ?: @""];
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

- (void)configureSearchErrorState {
    self.invitationView.hidden = YES;
    self.actionButton.hidden = YES;

    [self.iconImageView stopAnimating];
    self.iconImageView.animationImages = nil;
    self.iconImageView.image = [UIImage imageNamed:@"network_unavailable"];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result beginEditing];

    NSAttributedString *title =
        [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Network Unavailable", nil)
                                        attributes:@{NSFontAttributeName : self.boldFont}];
    [result appendAttributedString:title];

    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];

    NSAttributedString *subtitle =
        [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Unable to search for a user", nil)
                                        attributes:@{NSFontAttributeName : self.regularFont}];
    [result appendAttributedString:subtitle];

    [result endEditing];

    self.descriptionLabel.attributedText = result;
}

- (void)configureActionButtonForSearchUsers {
    self.invitationView.hidden = YES;
    self.actionButton.hidden = NO;
    self.actionButton.imageEdgeInsets = UIEdgeInsetsMake(0.0, -8.0, 0.0, 0.0);
    [self.actionButton setImage:[UIImage imageNamed:@"dp_search_add_contact"] forState:UIControlStateNormal];
    [self.actionButton setTitle:NSLocalizedString(@"Search for a User on the Dash Network", nil)
                       forState:UIControlStateNormal];
}

- (UIFont *)regularFont {
    return [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
}

- (UIFont *)boldFont {
    return [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
}

@end

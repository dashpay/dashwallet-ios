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

#import "DWExploreTestnetContentsView.h"

#import "DWUIKit.h"

@interface DWExploreTestnetContentsView () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) NSArray<NSString *> *cellIcons;
@property (nonatomic, strong) NSArray<NSString *> *cellTitles;
@property (nonatomic, strong) NSArray<NSString *> *cellSubtitles;

@end

@implementation DWExploreTestnetContentsView

@synthesize cellIcons;
@synthesize cellTitles;
@synthesize cellSubtitles;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_darkBlueColor];

        cellIcons = @[ @"image.explore.dash.wheretospend", @"image.explore.dash.atm" ];
        cellTitles = @[ NSLocalizedString(@"Where to Spend?", nil), NSLocalizedString(@"ATMs", nil) ];
        cellSubtitles = @[ NSLocalizedString(@"Find merchants who accept Dash as payment.", nil), NSLocalizedString(@"Find where to buy or sell DASH and other cryptocurrencies for cash.", nil) ];

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        contentView.layer.cornerRadius = 8.0;
        contentView.layer.masksToBounds = YES;
        contentView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner; // TL | TR
        [self addSubview:contentView];

        UIView *subContentView = [[UIView alloc] init];
        subContentView.translatesAutoresizingMaskIntoConstraints = NO;
        subContentView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        subContentView.layer.cornerRadius = 8.0;
        subContentView.layer.masksToBounds = YES;
        [contentView addSubview:subContentView];

        UITableView *tableView = [UITableView new];
        tableView.layer.cornerRadius = 8.0;
        tableView.layer.masksToBounds = YES;
        tableView.translatesAutoresizingMaskIntoConstraints = NO;
        tableView.scrollEnabled = false;
        tableView.delegate = self;
        tableView.dataSource = self;
        tableView.rowHeight = 80.0f;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        [tableView registerClass:[DWExploreTestnetContentsViewCell class] forCellReuseIdentifier:DWExploreTestnetContentsViewCell.dw_reuseIdentifier];
        [subContentView addSubview:tableView];

        CGFloat verticalPadding = 10;

        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [subContentView.heightAnchor constraintEqualToConstant:180],
            [subContentView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                     constant:15],
            [subContentView.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor
                                                                  constant:-34],
            [subContentView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                          constant:-15],
            [subContentView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                         constant:15],

            [tableView.topAnchor constraintEqualToAnchor:subContentView.topAnchor
                                                constant:verticalPadding],
            [tableView.bottomAnchor constraintEqualToAnchor:subContentView.bottomAnchor
                                                   constant:-verticalPadding],
            [tableView.trailingAnchor constraintEqualToAnchor:subContentView.trailingAnchor],
            [tableView.leadingAnchor constraintEqualToAnchor:subContentView.leadingAnchor],
        ]];
    }
    return self;
}

- (nonnull UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    NSString *icon = cellIcons[indexPath.row];
    NSString *title = cellTitles[indexPath.row];
    NSString *subtitle = cellSubtitles[indexPath.row];

    DWExploreTestnetContentsViewCell *cell = (DWExploreTestnetContentsViewCell *)[tableView dequeueReusableCellWithIdentifier:DWExploreTestnetContentsViewCell.dw_reuseIdentifier forIndexPath:indexPath];
    [cell setImage:[UIImage imageNamed:icon]];
    [cell setTitle:title];
    [cell setSubtitle:subtitle];

    if (indexPath.row == 1) {
        cell.separatorInset = UIEdgeInsetsMake(0, 2000, 0, 0);
    }

    return cell;
}

- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    if (indexPath.row == 0) {
        _whereToSpendHandler();
    }
    else {
        _atmHandler();
    }
}

@end

@interface DWExploreTestnetContentsViewCell ()
@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *descLabel;
@end

@implementation DWExploreTestnetContentsViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self configureHierarchy];
    }
    return self;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self configureHierarchy];
    }

    return self;
}

- (void)configureHierarchy {
    UIStackView *stackView = [UIStackView new];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.spacing = 10;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:stackView];

    UIStackView *imageStackView = [UIStackView new];
    imageStackView.translatesAutoresizingMaskIntoConstraints = NO;
    imageStackView.axis = UILayoutConstraintAxisVertical;
    imageStackView.spacing = 1;
    imageStackView.alignment = UIStackViewAlignmentLeading;
    [stackView addArrangedSubview:imageStackView];

    UIImageView *iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 34, 34)];
    iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    iconImageView.contentMode = UIViewContentModeCenter;
    [imageStackView addArrangedSubview:iconImageView];
    _iconImageView = iconImageView;

    [imageStackView addArrangedSubview:[UIView new]];

    UIStackView *labelsStackView = [UIStackView new];
    labelsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    labelsStackView.axis = UILayoutConstraintAxisVertical;
    labelsStackView.spacing = 1;
    labelsStackView.alignment = UIStackViewAlignmentLeading;
    [stackView addArrangedSubview:labelsStackView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.numberOfLines = 0;
    [labelsStackView addArrangedSubview:titleLabel];
    _titleLabel = titleLabel;

    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.textColor = [UIColor secondaryLabelColor];
    descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    descLabel.textAlignment = NSTextAlignmentLeft;
    descLabel.numberOfLines = 0;
    [labelsStackView addArrangedSubview:descLabel];
    _descLabel = descLabel;

    [labelsStackView addArrangedSubview:[UIView new]];

    [NSLayoutConstraint activateConstraints:@[
        [iconImageView.widthAnchor constraintEqualToConstant:34],
        [iconImageView.heightAnchor constraintEqualToConstant:34],

        [stackView.topAnchor constraintEqualToAnchor:self.contentView.safeAreaLayoutGuide.topAnchor
                                            constant:12],
        [stackView.bottomAnchor constraintEqualToAnchor:self.contentView.safeAreaLayoutGuide.bottomAnchor
                                               constant:-4],
        [stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                constant:15],
        [stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor]
    ]];
}

- (UIImage *)image {
    return self.iconImageView.image;
}

- (void)setImage:(UIImage *)image {
    self.iconImageView.image = image;
}

- (NSString *)title {
    return self.titleLabel.text;
}

- (void)setTitle:(NSString *)title {
    self.titleLabel.text = title;
}

- (NSString *)subtitle {
    return self.descLabel.text;
}

- (void)setSubtitle:(NSString *)subtitle {
    self.descLabel.text = subtitle;
}
@end

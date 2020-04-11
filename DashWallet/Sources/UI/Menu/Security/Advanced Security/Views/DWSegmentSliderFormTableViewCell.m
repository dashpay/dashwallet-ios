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

#import "DWSegmentSliderFormTableViewCell.h"

#import "DWSegmentSlider.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const SLIDER_DESCRIPTION_PADDING = 8.0;

@interface DWSegmentSliderFormTableViewCell ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *detailLabel;
@property (readonly, nonatomic, strong) DWSegmentSlider *segmentSlider;
@property (readonly, nonatomic, strong) UILabel *descriptionLabel;

@end

@implementation DWSegmentSliderFormTableViewCell

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
        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 2
                                                    forAxis:UILayoutConstraintAxisVertical];
        [contentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        detailLabel.backgroundColor = [UIColor dw_backgroundColor];
        detailLabel.textAlignment = NSTextAlignmentRight;
        detailLabel.textColor = [UIColor dw_dashBlueColor];
        detailLabel.numberOfLines = 0;
        detailLabel.lineBreakMode = NSLineBreakByWordWrapping;
        detailLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
        detailLabel.adjustsFontForContentSizeCategory = YES;
        detailLabel.minimumScaleFactor = 0.5;
        detailLabel.adjustsFontSizeToFitWidth = YES;
        [detailLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                     forAxis:UILayoutConstraintAxisHorizontal];
        [detailLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                     forAxis:UILayoutConstraintAxisVertical];
        [detailLabel setContentHuggingPriority:UILayoutPriorityDefaultLow - 1
                                       forAxis:UILayoutConstraintAxisHorizontal];
        [detailLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 1
                                       forAxis:UILayoutConstraintAxisVertical];
        [contentView addSubview:detailLabel];
        _detailLabel = detailLabel;

        DWSegmentSlider *segmentSlider = [[DWSegmentSlider alloc] initWithFrame:CGRectZero];
        segmentSlider.translatesAutoresizingMaskIntoConstraints = NO;
        [segmentSlider addTarget:self
                          action:@selector(segmentSliderAction:)
                forControlEvents:UIControlEventValueChanged];
        _segmentSlider = segmentSlider;

        UILabel *descriptionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        descriptionLabel.backgroundColor = [UIColor dw_backgroundColor];
        descriptionLabel.textAlignment = NSTextAlignmentLeft;
        descriptionLabel.textColor = [UIColor dw_quaternaryTextColor];
        descriptionLabel.numberOfLines = 0;
        descriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
        descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        descriptionLabel.adjustsFontForContentSizeCategory = YES;
        descriptionLabel.minimumScaleFactor = 0.5;
        descriptionLabel.adjustsFontSizeToFitWidth = YES;
        _descriptionLabel = descriptionLabel;

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ segmentSlider, descriptionLabel ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.spacing = SLIDER_DESCRIPTION_PADDING;
        [contentView addSubview:stackView];

        const CGFloat margin = DWDefaultMargin();
        const CGFloat padding = DW_FORM_CELL_VERTICAL_PADDING;

        NSLayoutConstraint *titleTopConstraint = [titleLabel.topAnchor constraintGreaterThanOrEqualToAnchor:contentView.topAnchor
                                                                                                   constant:padding];
        titleTopConstraint.priority = UILayoutPriorityRequired - 1;

        [NSLayoutConstraint activateConstraints:@[
            titleTopConstraint,
            [titleLabel.centerYAnchor constraintEqualToAnchor:detailLabel.centerYAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                     constant:margin],

            [detailLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                  constant:padding],
            [detailLabel.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                      constant:DW_FORM_CELL_SPACING],
            [detailLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                       constant:-margin],
            [detailLabel.widthAnchor constraintEqualToAnchor:titleLabel.widthAnchor],

            [stackView.topAnchor constraintEqualToAnchor:detailLabel.bottomAnchor
                                                constant:padding],
            [stackView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                    constant:margin],
            [stackView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                   constant:-padding],
            [stackView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                     constant:-margin],
        ]];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(contentSizeCategoryDidChangeNotification)
                                   name:UIContentSizeCategoryDidChangeNotification
                                 object:nil];

        [self setupObserving];
    }

    return self;
}

- (void)setupObserving {
    [self mvvm_observe:DW_KEYPATH(self, cellModel.title)
                  with:^(__typeof(self) self, NSString *value) {
                      self.titleLabel.text = value ?: @" ";
                  }];
}

- (void)setCellModel:(nullable DWSegmentSliderFormCellModel *)cellModel {
    _cellModel = cellModel;

    [self setupSlider];
    [self reloadAttributedData];
}

- (BOOL)shouldAnimatePressWhenHighlighted {
    return NO;
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification {
    [self reloadAttributedData];
}

#pragma mark - Actions

- (void)segmentSliderAction:(DWSegmentSlider *)sender {
    self.cellModel.selectedItemIndex = sender.selectedItemIndex;
    self.cellModel.didChangeValueBlock(self.cellModel, self);

    [self reloadAttributedData];
}

#pragma mark - Private

- (void)reloadAttributedData {
    DWSegmentSliderFormCellModel *cellModel = self.cellModel;
    if (!cellModel) {
        return;
    }

    UIFont *font = [DWSegmentSlider valuesTextFont];
    UIColor *color = [DWSegmentSlider valuesTextColor];
    if (cellModel.sliderLeftAttributedTextBuilder) {
        self.segmentSlider.leftAttributedText = cellModel.sliderLeftAttributedTextBuilder(font, color);
    }
    if (cellModel.sliderRightAttributedTextBuilder) {
        self.segmentSlider.rightAttributedText = cellModel.sliderRightAttributedTextBuilder(font, color);
    }

    if (cellModel.detailBuilder) {
        UIFont *font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
        UIColor *color = [UIColor dw_darkTitleColor];
        self.detailLabel.attributedText = cellModel.detailBuilder(font, color);
    }
    else {
        self.detailLabel.attributedText = nil;
        self.detailLabel.text = @" ";
    }

    if (cellModel.descriptionTextBuilder) {
        UIFont *font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        UIColor *color = [UIColor dw_quaternaryTextColor];
        self.descriptionLabel.hidden = NO;
        self.descriptionLabel.attributedText = cellModel.descriptionTextBuilder(font, color);
    }
    else {
        self.descriptionLabel.hidden = YES;
        self.descriptionLabel.attributedText = nil;
    }
}

- (void)setupSlider {
    DWSegmentSliderFormCellModel *cellModel = self.cellModel;

    self.segmentSlider.values = cellModel.sliderValues;
    self.segmentSlider.selectedItemIndex = cellModel.selectedItemIndex;
    self.segmentSlider.leftText = cellModel.sliderLeftText;
    self.segmentSlider.rightText = cellModel.sliderRightText;
}

@end

NS_ASSUME_NONNULL_END

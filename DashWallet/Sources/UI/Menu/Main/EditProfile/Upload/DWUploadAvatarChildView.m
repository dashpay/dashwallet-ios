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

#import "DWUploadAvatarChildView.h"

#import "DWActionButton.h"
#import "DWHourGlassAnimationView.h"
#import "DWUIKit.h"
#import "DWUploadAvatarModel.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const ViewCornerRadius = 8.0;
static CGSize const ImageSize = {87.0, 87.0};
static CGSize const IconSize = {28.0, 28.0};
static CGFloat const ButtonHeight = 39.0;

@interface DWUploadAvatarChildView ()

@property (readonly, nonatomic, strong) UIImageView *imageView;
@property (readonly, nonatomic, strong) DWHourGlassAnimationView *animationView;
@property (readonly, nonatomic, strong) UIImageView *errorImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *subtitleLabel;
@property (readonly, strong, nonatomic) UIButton *cancelButton;
@property (readonly, strong, nonatomic) UIButton *retryButton;

@end

NS_ASSUME_NONNULL_END

@implementation DWUploadAvatarChildView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];
        self.clipsToBounds = YES;
        self.layer.cornerRadius = ViewCornerRadius;


        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = self.backgroundColor;

        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.layer.cornerRadius = ImageSize.width / 2.0;
        imageView.layer.masksToBounds = YES;
        [contentView addSubview:imageView];
        _imageView = imageView;

        UIView *titleContentView = [[UIView alloc] init];
        titleContentView.translatesAutoresizingMaskIntoConstraints = NO;
        titleContentView.backgroundColor = self.backgroundColor;
        [contentView addSubview:titleContentView];

        UIView *iconView = [[UIView alloc] init];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [titleContentView addSubview:iconView];

        DWHourGlassAnimationView *animationView = [[DWHourGlassAnimationView alloc] initWithFrame:CGRectZero];
        animationView.translatesAutoresizingMaskIntoConstraints = NO;
        [iconView addSubview:animationView];
        _animationView = animationView;

        UIImageView *errorImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon_error"]];
        errorImageView.translatesAutoresizingMaskIntoConstraints = NO;
        errorImageView.contentMode = UIViewContentModeScaleAspectFit;
        [iconView addSubview:errorImageView];
        _errorImageView = errorImageView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        [titleContentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.textColor = [UIColor dw_secondaryTextColor];
        subtitleLabel.textAlignment = NSTextAlignmentCenter;
        subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        subtitleLabel.adjustsFontForContentSizeCategory = YES;
        subtitleLabel.adjustsFontSizeToFitWidth = YES;
        [contentView addSubview:subtitleLabel];
        _subtitleLabel = subtitleLabel;

        DWActionButton *cancelButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        cancelButton.usedOnDarkBackground = NO;
        cancelButton.small = YES;
        cancelButton.inverted = YES;
        [cancelButton setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];
        [cancelButton addTarget:self
                         action:@selector(cancelButtonAction:)
               forControlEvents:UIControlEventTouchUpInside];
        _cancelButton = cancelButton;

        DWActionButton *retryButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        retryButton.translatesAutoresizingMaskIntoConstraints = NO;
        retryButton.usedOnDarkBackground = NO;
        retryButton.small = YES;
        retryButton.inverted = NO;
        [retryButton setTitle:NSLocalizedString(@"Try again", nil) forState:UIControlStateNormal];
        [retryButton addTarget:self
                        action:@selector(retryButtonAction:)
              forControlEvents:UIControlEventTouchUpInside];
        _retryButton = retryButton;

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ contentView, cancelButton, retryButton ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.spacing = 54.0;
        stackView.alignment = UIStackViewAlignmentCenter;
        [self addSubview:stackView];

        const CGFloat padding = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [stackView.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
            [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:stackView.bottomAnchor],
            [stackView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:padding],
            [self.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor
                                                constant:padding],

            [imageView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                constant:padding],
            [imageView.widthAnchor constraintEqualToConstant:ImageSize.width],
            [imageView.heightAnchor constraintEqualToConstant:ImageSize.height],
            [imageView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],

            [titleContentView.topAnchor constraintEqualToAnchor:imageView.bottomAnchor
                                                       constant:12],
            [titleContentView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
            [titleContentView.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentView.leadingAnchor],
            [contentView.trailingAnchor constraintGreaterThanOrEqualToAnchor:titleContentView.trailingAnchor],

            [iconView.topAnchor constraintEqualToAnchor:titleContentView.topAnchor],
            [iconView.leadingAnchor constraintEqualToAnchor:titleContentView.leadingAnchor],
            [titleContentView.bottomAnchor constraintEqualToAnchor:iconView.bottomAnchor],
            [iconView.widthAnchor constraintEqualToConstant:IconSize.width],
            [iconView.heightAnchor constraintEqualToConstant:IconSize.height],

            [animationView.topAnchor constraintEqualToAnchor:iconView.topAnchor],
            [animationView.leadingAnchor constraintEqualToAnchor:iconView.leadingAnchor],
            [iconView.trailingAnchor constraintEqualToAnchor:animationView.trailingAnchor],
            [iconView.bottomAnchor constraintEqualToAnchor:animationView.bottomAnchor],

            [errorImageView.topAnchor constraintEqualToAnchor:iconView.topAnchor],
            [errorImageView.leadingAnchor constraintEqualToAnchor:iconView.leadingAnchor],
            [iconView.trailingAnchor constraintEqualToAnchor:errorImageView.trailingAnchor],
            [iconView.bottomAnchor constraintEqualToAnchor:errorImageView.bottomAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:titleContentView.topAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor],
            [titleContentView.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
            [titleContentView.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

            [subtitleLabel.topAnchor constraintEqualToAnchor:titleContentView.bottomAnchor
                                                    constant:2],
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:subtitleLabel.trailingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor],

            [retryButton.heightAnchor constraintEqualToConstant:ButtonHeight],
            [cancelButton.heightAnchor constraintEqualToConstant:ButtonHeight],
        ]];

        [self mvvm_observe:DW_KEYPATH(self, model.state)
                      with:^(typeof(self) self, id value) {
                          switch (self.model.state) {
                              case DWUploadAvatarModelState_Loading:
                                  self.titleLabel.text = NSLocalizedString(@"Please Wait", nil);
                                  self.subtitleLabel.text = NSLocalizedString(@"Uploading your picture to the network", nil);
                                  self.retryButton.hidden = YES;
                                  self.cancelButton.hidden = NO;
                                  self.errorImageView.hidden = YES;

                                  self.animationView.hidden = NO;
                                  [self.animationView startAnimating];

                                  break;
                              case DWUploadAvatarModelState_Error:
                                  self.titleLabel.text = NSLocalizedString(@"Upload Error", nil);
                                  self.subtitleLabel.text = NSLocalizedString(@"Unable to upload your picture. Please try again.", nil);
                                  self.retryButton.hidden = NO;
                                  self.cancelButton.hidden = YES;
                                  self.errorImageView.hidden = NO;

                                  [self.animationView stopAnimating];
                                  self.animationView.hidden = YES;

                                  break;
                              case DWUploadAvatarModelState_Success:
                                  [self.delegate uploadAvatarChildViewDidFinish:self];
                                  break;
                          }
                      }];
    }
    return self;
}

- (void)setModel:(DWUploadAvatarModel *)model {
    _model = model;

    self.imageView.image = model.image;
}

- (void)cancelButtonAction:(UIButton *)sender {
    [self.model cancel];
    [self.delegate uploadAvatarChildViewDidCancel:self];
}

- (void)retryButtonAction:(UIButton *)sender {
    [self.model retry];
}

@end

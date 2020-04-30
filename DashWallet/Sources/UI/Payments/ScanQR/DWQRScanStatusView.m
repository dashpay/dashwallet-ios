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

#import "DWQRScanStatusView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWQRScanStatusView ()

@property (readonly, nonatomic, strong) UIImageView *imageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *descriptionLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWQRScanStatusView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = self.backgroundColor;
        [self addSubview:contentView];

        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:imageView];
        _imageView = imageView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.numberOfLines = 0;
        titleLabel.minimumScaleFactor = 0.5;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        [contentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *descriptionLabel = [[UILabel alloc] init];
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        descriptionLabel.adjustsFontForContentSizeCategory = YES;
        descriptionLabel.textColor = [UIColor dw_secondaryTextColor];
        descriptionLabel.textAlignment = NSTextAlignmentCenter;
        descriptionLabel.numberOfLines = 0;
        descriptionLabel.minimumScaleFactor = 0.5;
        descriptionLabel.adjustsFontSizeToFitWidth = YES;
        [contentView addSubview:descriptionLabel];
        _descriptionLabel = descriptionLabel;

        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];
        [descriptionLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 1
                                                          forAxis:UILayoutConstraintAxisVertical];
        [imageView setContentCompressionResistancePriority:UILayoutPriorityRequired - 2
                                                   forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                      constant:8],
            [self.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                constant:8],
            [contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [contentView.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor
                                                               constant:4],
            [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentView.bottomAnchor
                                                           constant:4],

            [imageView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [imageView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:imageView.bottomAnchor
                                                 constant:16],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

            [descriptionLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                       constant:16],
            [descriptionLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:descriptionLabel.trailingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:descriptionLabel.bottomAnchor],
        ]];
    }
    return self;
}

- (void)updateStatus:(DWQRScanStatus)status errorMessage:(NSString *)errorMessage {
    switch (status) {
        case DWQRScanStatus_None: {
            [self.imageView stopAnimating];
            self.imageView.animationImages = nil;
            self.imageView.image = nil;
            self.titleLabel.text = nil;
            self.descriptionLabel.text = nil;

            break;
        }
        case DWQRScanStatus_Connecting: {
            NSArray<UIImage *> *images = @[
                [UIImage imageNamed:@"connection_animation_1"],
                [UIImage imageNamed:@"connection_animation_2"],
                [UIImage imageNamed:@"connection_animation_3"],
                [UIImage imageNamed:@"connection_animation_4"],
                [UIImage imageNamed:@"connection_animation_1"],
            ];
            self.imageView.image = nil;
            self.imageView.animationImages = images;
            self.imageView.animationDuration = 0.75;
            self.imageView.animationRepeatCount = 0;
            [self.imageView startAnimating];
            self.titleLabel.text = NSLocalizedString(@"Please Wait", nil);
            self.descriptionLabel.text = NSLocalizedString(@"Connecting to payment server", nil);

            break;
        }
        case DWQRScanStatus_InvalidPaymentRequest: {
            [self.imageView stopAnimating];
            self.imageView.animationImages = nil;
            self.imageView.image = [UIImage imageNamed:@"unable_to_connect"];
            self.titleLabel.text = NSLocalizedString(@"Invalid Payment Request", nil);
            self.descriptionLabel.text = errorMessage ?: NSLocalizedString(@"Please try scanning again", nil);

            break;
        }
        case DWQRScanStatus_InvalidQR: {
            [self.imageView stopAnimating];
            self.imageView.animationImages = nil;
            self.imageView.image = [UIImage imageNamed:@"invalid_qr"];
            self.titleLabel.text = NSLocalizedString(@"Invalid QR Code", nil);
            self.descriptionLabel.text = errorMessage ?: NSLocalizedString(@"Please try scanning again", nil);

            break;
        }
    }
}

@end

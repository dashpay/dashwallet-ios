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

#import "DWImgurInfoChildView.h"

#import "DWActionButton.h"
#import "DWBorderedActionButton.h"
#import "DWImgurItemView.h"
#import "DWUIKit.h"

static CGFloat const ViewCornerRadius = 8.0;
static CGFloat const ButtonHeight = 39.0;

NS_ASSUME_NONNULL_BEGIN

@interface DWImgurInfoChildView ()

@property (nonatomic, strong) DWImgurItemView *item1;

@end

NS_ASSUME_NONNULL_END

@implementation DWImgurInfoChildView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];
        self.layer.cornerRadius = ViewCornerRadius;
        self.layer.masksToBounds = YES;

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
        title.textColor = [UIColor dw_darkTitleColor];
        title.text = NSLocalizedString(@"Images Privacy Policy", nil);
        title.textAlignment = NSTextAlignmentCenter;
        [self addSubview:title];

        DWImgurItemView *item1 = [[DWImgurItemView alloc] init];
        item1.translatesAutoresizingMaskIntoConstraints = NO;
        _item1 = item1;

        DWImgurItemView *item2 = [[DWImgurItemView alloc] init];
        item2.translatesAutoresizingMaskIntoConstraints = NO;
        item2.text = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Image uploaded can be viewed publicly by anyone.", nil)];

        DWImgurItemView *item3 = [[DWImgurItemView alloc] init];
        item3.translatesAutoresizingMaskIntoConstraints = NO;
        item3.text = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"You can always delete the image uploaded, as long as you have access to this wallet.", nil)];

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ item1, item2, item3 ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.spacing = 20.0;
        [self addSubview:stackView];

        DWActionButton *okButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        okButton.translatesAutoresizingMaskIntoConstraints = NO;
        okButton.usedOnDarkBackground = NO;
        okButton.small = YES;
        okButton.inverted = NO;
        [okButton setTitle:NSLocalizedString(@"Agree", nil) forState:UIControlStateNormal];
        [okButton addTarget:self
                      action:@selector(okButtonAction)
            forControlEvents:UIControlEventTouchUpInside];

        DWBorderedActionButton *cancelButton = [[DWBorderedActionButton alloc] initWithFrame:CGRectZero];
        cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        [cancelButton setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];
        [cancelButton addTarget:self
                         action:@selector(cancelButtonAction)
               forControlEvents:UIControlEventTouchUpInside];

        UIStackView *buttonsStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ okButton, cancelButton ]];
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = NO;
        buttonsStackView.axis = UILayoutConstraintAxisHorizontal;
        buttonsStackView.distribution = UIStackViewDistributionFillEqually;
        buttonsStackView.spacing = 8.0;
        buttonsStackView.alignment = UIStackViewAlignmentCenter;
        [self addSubview:buttonsStackView];

        [NSLayoutConstraint activateConstraints:@[
            [title.topAnchor constraintEqualToAnchor:self.topAnchor
                                            constant:32.0],
            [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                constant:16.0],
            [self.trailingAnchor constraintEqualToAnchor:title.trailingAnchor
                                                constant:16.0],

            [stackView.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                                constant:18.0],
            [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:25.0],
            [self.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor
                                                constant:25.0],


            [buttonsStackView.topAnchor constraintEqualToAnchor:stackView.bottomAnchor
                                                       constant:40],
            [buttonsStackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.bottomAnchor constraintEqualToAnchor:buttonsStackView.bottomAnchor
                                              constant:32.0],

            [okButton.heightAnchor constraintEqualToConstant:ButtonHeight],
            [cancelButton.heightAnchor constraintEqualToConstant:ButtonHeight],
            [buttonsStackView.heightAnchor constraintEqualToConstant:ButtonHeight],
        ]];

        [self updateItem1Text];
    }
    return self;
}

- (void)okButtonAction {
    [self.delegate imgurInfoChildViewAcceptAction:self];
}

- (void)cancelButtonAction {
    [self.delegate imgurInfoChildViewCancelAction:self];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self updateItem1Text];
}

- (void)updateItem1Text {
    NSString *s1 = NSLocalizedString(@"The image you select will be uploaded to Imgur anonymously.",
                                     @"Don't translate 'Imgur'");
    NSRange range = [s1 rangeOfString:@"Imgur"];
    NSMutableAttributedString *att1 = [[NSMutableAttributedString alloc] initWithString:s1];
    if (range.location != NSNotFound) {
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        attachment.image = [UIImage imageNamed:@"logo_imgur_small"];
        attachment.bounds = CGRectMake(0.0, -4.0, 45.0, 16.0);
        NSAttributedString *imageString = [NSAttributedString attributedStringWithAttachment:attachment];
        [att1 replaceCharactersInRange:range withAttributedString:imageString];
    }
    self.item1.text = att1;
}

@end

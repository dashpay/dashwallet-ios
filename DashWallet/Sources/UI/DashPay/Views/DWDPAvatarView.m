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

#import "DWDPAvatarView.h"

#import "DWUIKit.h"
#import "UIColor+DWDashPay.h"

#import <DashSync/DashSync.h>
#import <SDWebImage/SDWebImage.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWDPAvatarView ()

@property (readonly, nonatomic, strong) UIImageView *imageView;
@property (readonly, nonatomic, strong) UILabel *letterLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPAvatarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.layer.cornerRadius = CGRectGetWidth(self.bounds) / 2.0;

    self.imageView.frame = self.bounds;
    self.letterLabel.frame = self.bounds;
}

- (void)setBackgroundMode:(DWDPAvatarBackgroundMode)backgroundMode {
    _backgroundMode = backgroundMode;

    [self updateBackgroundColor];
}

- (void)setBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    _blockchainIdentity = blockchainIdentity;

    NSString *username = blockchainIdentity.currentDashpayUsername;
    NSURL *url = [NSURL URLWithString:blockchainIdentity.avatarPath];
    __weak typeof(self) weakSelf = self;
    [self.imageView
        sd_setImageWithURL:url
                 completed:^(UIImage *_Nullable image, NSError *_Nullable error, SDImageCacheType cacheType, NSURL *_Nullable imageURL) {
                     __strong typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return;
                     }

                     if (image) {
                         strongSelf.imageView.hidden = NO;
                         strongSelf.letterLabel.hidden = YES;
                         strongSelf.imageView.image = image;
                     }
                     else {
                         [strongSelf setUsername:username];
                     }
                 }];
}

- (void)configureWithUsername:(NSString *)username {
    [self setUsername:username];
}

- (void)setUsername:(NSString *)username {
    self.letterLabel.hidden = NO;
    self.imageView.hidden = YES;

    if (username.length >= 1) {
        NSString *firstLetter = [username substringToIndex:1];
        self.letterLabel.text = [firstLetter uppercaseString];

        [self updateBackgroundColor];
    }
    else {
        self.letterLabel.text = nil;
        self.layer.backgroundColor = [UIColor dw_dashBlueColor].CGColor;
    }
}

- (void)setAsDashPlaceholder {
    self.letterLabel.hidden = YES;
    self.imageView.hidden = NO;

    self.layer.backgroundColor = [UIColor dw_dashBlueColor].CGColor;

    self.imageView.tintColor = [UIColor whiteColor];
    self.imageView.contentMode = UIViewContentModeCenter;
    self.imageView.image = [UIImage imageNamed:@"icon_dash_small"];
}

- (void)setSmall:(BOOL)small {
    _small = small;

    if (small) {
        self.letterLabel.font = [UIFont dw_regularFontOfSize:20];
    }
    else {
        self.letterLabel.font = [UIFont dw_regularFontOfSize:30];
    }
}

#pragma mark - Private

- (void)setup {
    self.layer.backgroundColor = [UIColor dw_dashBlueColor].CGColor;
    self.layer.masksToBounds = YES;

    UIImageView *imageView = [[UIImageView alloc] init];
    [self addSubview:imageView];
    _imageView = imageView;

    UILabel *letterLabel = [[UILabel alloc] init];
    letterLabel.font = [UIFont dw_regularFontOfSize:30];
    letterLabel.textAlignment = NSTextAlignmentCenter;
    letterLabel.textColor = [UIColor dw_lightTitleColor];
    [self addSubview:letterLabel];
    _letterLabel = letterLabel;
}

- (void)updateBackgroundColor {
    UIColor *color = nil;
    switch (self.backgroundMode) {
        case DWDPAvatarBackgroundMode_DashBlue:
            color = [UIColor dw_dashBlueColor];
            break;

        case DWDPAvatarBackgroundMode_Random: {
            color = [UIColor dw_colorWithUsername:self.letterLabel.text];
            break;
        }
    }
    NSParameterAssert(color);
    self.layer.backgroundColor = color.CGColor;
}

@end

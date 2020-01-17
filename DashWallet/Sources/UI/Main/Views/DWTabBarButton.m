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

#import "DWTabBarButton.h"

#import <DashSync/UIImage+DSUtils.h>

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static UIColor *ActiveButtonColor(void) {
    return [UIColor dw_dashBlueColor];
}

static UIColor *InactiveButtonColor(void) {
    return [UIColor dw_tabbarInactiveButtonColor];
}


@interface DWTabBarButton ()

@property (readonly, strong, nonatomic) UIImageView *iconImageView;

@end

@implementation DWTabBarButton

- (instancetype)initWithType:(DWTabBarButtonType)type {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        UIImage *image = nil;
        switch (type) {
            case DWTabBarButtonType_Home:
                image = [UIImage imageNamed:@"tabbar_home_icon"];
                break;
            case DWTabBarButtonType_Contacts:
                image = [UIImage imageNamed:@"tabbar_contacts_icon"];
                break;
            case DWTabBarButtonType_Others:
                image = [UIImage imageNamed:@"tabbar_other_icon"];
                break;
        }

        UIImage *activeImage = [image ds_imageWithTintColor:ActiveButtonColor()];
        UIImage *inactiveImage = [image ds_imageWithTintColor:InactiveButtonColor()];

        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:inactiveImage
                                                       highlightedImage:activeImage];
        iconImageView.frame = self.bounds;
        iconImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        iconImageView.contentMode = UIViewContentModeCenter;
        [self addSubview:iconImageView];
        _iconImageView = iconImageView;
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];

    self.iconImageView.highlighted = selected;
}

@end

NS_ASSUME_NONNULL_END

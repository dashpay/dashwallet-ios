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

@interface DWDPAvatarView ()

@property (readonly, nonatomic, strong) UILabel *letterLabel;

@end

@implementation DWDPAvatarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.backgroundColor = [UIColor dw_dashBlueColor].CGColor;
        self.layer.masksToBounds = YES;
        self.layer.shouldRasterize = YES;

        UILabel *letterLabel = [[UILabel alloc] init];
        letterLabel.font = [UIFont dw_regularFontOfSize:30];
        letterLabel.textAlignment = NSTextAlignmentCenter;
        letterLabel.textColor = [UIColor dw_lightTitleColor];
        [self addSubview:letterLabel];
        _letterLabel = letterLabel;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.layer.cornerRadius = CGRectGetWidth(self.bounds) / 2.0;

    self.letterLabel.frame = self.bounds;
}

- (NSString *)letter {
    return self.letterLabel.text;
}

- (void)setLetter:(NSString *)letter {
    self.letterLabel.text = letter;
}

@end

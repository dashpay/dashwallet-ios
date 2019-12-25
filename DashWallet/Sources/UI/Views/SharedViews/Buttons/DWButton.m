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

#import "DWButton.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWButton

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self dwButton_setup];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self dwButton_setup];
    }
    return self;
}

- (void)dwButton_setup {
    self.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.5;
    self.titleLabel.lineBreakMode = NSLineBreakByClipping;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(setNeedsLayout)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

@end

NS_ASSUME_NONNULL_END

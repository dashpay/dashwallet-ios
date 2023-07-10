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

#import "DWDPGenericImageItemView.h"

@implementation DWDPGenericImageItemView

@synthesize imageView = _imageView;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup_imageItemView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup_imageItemView];
    }
    return self;
}

- (void)setup_imageItemView {
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeCenter;
    [self.accessoryView addSubview:imageView];
    _imageView = imageView;

    [imageView setContentCompressionResistancePriority:UILayoutPriorityRequired - 10 forAxis:UILayoutConstraintAxisHorizontal];
    [imageView setContentCompressionResistancePriority:UILayoutPriorityRequired - 10 forAxis:UILayoutConstraintAxisVertical];

    [NSLayoutConstraint activateConstraints:@[
        [imageView.topAnchor constraintEqualToAnchor:self.accessoryView.topAnchor],
        [imageView.leadingAnchor constraintEqualToAnchor:self.accessoryView.leadingAnchor],
        [self.accessoryView.trailingAnchor constraintEqualToAnchor:imageView.trailingAnchor],
        [self.accessoryView.bottomAnchor constraintEqualToAnchor:imageView.bottomAnchor],
    ]];
}

@end

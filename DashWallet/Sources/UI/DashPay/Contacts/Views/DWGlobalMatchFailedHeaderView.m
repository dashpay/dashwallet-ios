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

#import "DWGlobalMatchFailedHeaderView.h"

#import "DWNetworkUnavailableView.h"
#import "DWUIKit.h"

@implementation DWGlobalMatchFailedHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        DWNetworkUnavailableView *view = [[DWNetworkUnavailableView alloc] initWithFrame:CGRectZero];
        view.translatesAutoresizingMaskIntoConstraints = NO;
        view.error = NSLocalizedString(@"Unable to provide suggestions", nil);
        [self addSubview:view];

        UILayoutGuide *guide = self.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [view.topAnchor constraintEqualToAnchor:self.topAnchor
                                           constant:32.0],
            [view.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:view.bottomAnchor
                                              constant:32.0],
        ]];
    }
    return self;
}

@end

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

#import "DWCenteredTableView.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWCenteredTableView

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGFloat viewHeight = CGRectGetHeight(self.frame);
    const CGFloat tableViewContentHeight = self.contentSize.height;
    const CGFloat marginHeight = MAX(0.0, (viewHeight - tableViewContentHeight) / 2.0);

    self.contentInset = UIEdgeInsetsMake(marginHeight, 0.0, -marginHeight, 0.0);
}

@end

NS_ASSUME_NONNULL_END

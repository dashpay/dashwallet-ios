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

#import "DWContactsContentViewController.h"

#import "DWBaseContactsContentViewController+DWProtected.h"

#import "DWUIKit.h"

@implementation DWContactsContentViewController

@dynamic delegate;

- (NSUInteger)maxVisibleContactRequestsCount {
    return 3;
}

#pragma mark - DWContactsSearchPlaceholderViewDelegate

- (void)contactsSearchPlaceholderView:(DWContactsSearchPlaceholderView *)view searchAction:(UIButton *)sender {
    [self.delegate contactsContentController:self globalSearchButtonAction:sender];
}

#pragma mark - DWFilterHeaderViewDelegate

- (void)filterHeaderView:(DWFilterHeaderView *)view filterButtonAction:(UIView *)sender {
    [self.delegate contactsContentController:self contactsFilterButtonAction:sender];
}

#pragma mark - DWTitleActionHeaderViewDelegate

- (void)titleActionHeaderView:(DWTitleActionHeaderView *)view buttonAction:(UIView *)sender {
    [self.delegate contactsContentController:self contactRequestsButtonAction:sender];
}

@end

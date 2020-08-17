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

#import "DWVerticalContactCell.h"

#import "DWDPAvatarView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWVerticalContactCell ()

@property (strong, nonatomic) IBOutlet DWDPAvatarView *avatarView;
@property (strong, nonatomic) IBOutlet UILabel *usernameLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWVerticalContactCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.avatarView.small = YES;
    self.avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
    self.usernameLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];
}

- (void)setUserItem:(id<DWDPBasicUserItem>)userItem {
    _userItem = userItem;

    self.avatarView.username = userItem.username;
    self.usernameLabel.text = userItem.displayName ?: userItem.username;
}

@end

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

#import "DWNotificationIgnoredRequestItem.h"

#import <DashSync/DashSync.h>

#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationIgnoredRequestItem ()

@property (nullable, nonatomic, copy) NSString *subtitle;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationIgnoredRequestItem

@synthesize title = _title;
@synthesize date = _date;

- (instancetype)initWithFriendRequestEntity:(DSFriendRequestEntity *)friendRequestEntity {
    self = [super init];
    if (self) {
        _friendRequestEntity = friendRequestEntity;

        // TODO: set real date
        _date = [NSDate date];
    }
    return self;
}

- (DWNotificationDetailsType)type {
    return DWNotificationDetailsType_IgnoredRequest;
}

- (NSAttributedString *)title {
    if (_title == nil) {
        DSBlockchainIdentityEntity *blockchainIdentity = self.friendRequestEntity.sourceContact.associatedBlockchainIdentity;
        DSBlockchainIdentityUsernameEntity *username = blockchainIdentity.usernames.anyObject;
        NSString *plainUsername = [username.stringValue copy];

        NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%@ has sent you a contact request", @"Username has sent you a contact request"), plainUsername];

        NSMutableAttributedString *result = [[NSMutableAttributedString alloc]
            initWithString:title
                attributes:@{
                    NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2],
                    NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
                }];
        [result beginEditing];
        NSRange range = [title rangeOfString:plainUsername];
        if (range.location != NSNotFound) {
            [result setAttributes:@{
                NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1],
                NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
            }
                            range:range];
        }
        [result endEditing];
        _title = [result copy];
    }
    return _title;
}

- (NSString *)subtitleWithFormatter:(NSDateFormatter *)formatter {
    if (self.subtitle == nil) {
        self.subtitle = [formatter stringFromDate:self.date];
    }
    return self.subtitle;
}

@end

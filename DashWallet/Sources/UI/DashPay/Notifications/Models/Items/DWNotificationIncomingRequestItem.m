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

#import "DWNotificationIncomingRequestItem.h"

#import <DashSync/DashSync.h>

#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationIncomingRequestItem ()

@property (nullable, nonatomic, copy) NSString *subtitle;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationIncomingRequestItem

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
    return DWNotificationDetailsType_IncomingRequest;
}

- (NSAttributedString *)title {
    if (_title == nil) {
        DSBlockchainIdentityEntity *blockchainIdentity = self.friendRequestEntity.sourceContact.associatedBlockchainIdentity;
        DSBlockchainIdentityUsernameEntity *username = blockchainIdentity.usernames.anyObject;
        NSString *plainTitle = [username.stringValue copy];

        NSAttributedString *title = [[NSAttributedString alloc]
            initWithString:plainTitle
                attributes:@{
                    NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1],
                    NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
                }];
        _title = title;
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

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

#import "DWDPIgnoredRequestNotificationObject.h"

#import "UIFont+DWDPItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPIgnoredRequestNotificationObject ()

@property (readonly, nonatomic, strong) NSDateFormatter *dateFormatter;
@property (readonly, nonatomic, strong) NSDate *date;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPIgnoredRequestNotificationObject

@synthesize title = _title;
@synthesize subtitle = _subtitle;

- (instancetype)initWithFriendRequestEntity:(DSFriendRequestEntity *)friendRequestEntity
                              dateFormatter:(NSDateFormatter *)dateFormatter {
    self = [super initWithFriendRequestEntity:friendRequestEntity];
    if (self) {
        _dateFormatter = dateFormatter;
        // TODO: get from entity
        _date = [NSDate date];
    }
    return self;
}

- (NSAttributedString *)title {
    if (_title == nil) {
        NSString *name = self.displayName ?: self.username;
        NSString *plainTitle = [NSString stringWithFormat:
                                             NSLocalizedString(@"%@ has sent you a contact request", nil),
                                             name];

        NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:plainTitle attributes:@{NSFontAttributeName : [UIFont dw_itemSubtitleFont]}];

        NSRange range = [plainTitle rangeOfString:name];
        if (range.location != NSNotFound) {
            [title setAttributes:@{NSFontAttributeName : [UIFont dw_itemTitleFont]} range:range];
        }

        _title = [title copy];
    }
    return _title;
}

- (NSString *)subtitle {
    if (_subtitle == nil) {
        _subtitle = [self.dateFormatter stringFromDate:self.date];
    }
    return _subtitle;
}

@end

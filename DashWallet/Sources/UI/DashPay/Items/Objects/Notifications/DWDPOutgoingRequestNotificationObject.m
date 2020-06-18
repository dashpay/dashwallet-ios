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

#import "DWDPOutgoingRequestNotificationObject.h"

#import "DWDateFormatter.h"
#import "DWEnvironment.h"
#import "UIFont+DWDPItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPOutgoingRequestNotificationObject ()

@property (readonly, nonatomic, assign, getter=isInitiatedByMe) BOOL initiatedByMe;

@end

NS_ASSUME_NONNULL_END


@implementation DWDPOutgoingRequestNotificationObject

@synthesize title = _title;
@synthesize subtitle = _subtitle;
@synthesize date = _date;

- (instancetype)initWithFriendRequestEntity:(DSFriendRequestEntity *)friendRequestEntity
                         blockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity
                            isInitiatedByMe:(BOOL)isInitiatedByMe {
    self = [super initWithFriendRequestEntity:friendRequestEntity blockchainIdentity:blockchainIdentity];
    if (self) {
        _date = [NSDate dateWithTimeIntervalSince1970:friendRequestEntity.timestamp];
        _initiatedByMe = isInitiatedByMe;
    }
    return self;
}

- (NSAttributedString *)title {
    if (_title == nil) {
        NSString *name = self.displayName ?: self.username;
        NSString *format = self.isInitiatedByMe
                               ? NSLocalizedString(@"You sent the contact request to %@", nil)
                               : NSLocalizedString(@"You accepted the contact request from %@", nil);
        NSString *plainTitle = [NSString stringWithFormat:format, name];

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
        _subtitle = [[DWDateFormatter sharedInstance] shortStringFromDate:self.date];
    }
    return _subtitle;
}


@end

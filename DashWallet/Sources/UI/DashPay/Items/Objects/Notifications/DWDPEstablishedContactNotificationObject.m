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

#import "DWDPEstablishedContactNotificationObject.h"

#import <DashSync/DashSync.h>

#import "DWDateFormatter.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPEstablishedContactNotificationObject ()

@property (readonly, nonatomic, strong) NSDate *date;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPEstablishedContactNotificationObject

@synthesize subtitle = _subtitle;

- (instancetype)initWithDashpayUserEntity:(DSDashpayUserEntity *)userEntity {
    self = [super initWithDashpayUserEntity:userEntity];
    if (self) {
        // TODO: get from entity
        _date = [NSDate date];
    }
    return self;
}

- (NSString *)subtitle {
    if (_subtitle == nil) {
        _subtitle = [[DWDateFormatter sharedInstance] shortStringFromDate:self.date];
    }
    return _subtitle;
}

@end

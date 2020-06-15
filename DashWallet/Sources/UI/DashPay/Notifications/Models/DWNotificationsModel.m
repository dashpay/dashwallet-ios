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

#import "DWNotificationsModel.h"

#import "DWDashPayContactsActions.h"
#import "DWEnvironment.h"
#import "DWNotificationsDataSourceObject.h"
#import "DWNotificationsProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsModel ()

@property (readonly, nonatomic, strong) DWNotificationsDataSourceObject *aggregateDataSource;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _aggregateDataSource = [[DWNotificationsDataSourceObject alloc] init];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(notificationsDidUpdate)
                                                     name:DWNotificationsProviderDidUpdateNotification
                                                   object:nil];
        [self notificationsDidUpdate]; // initial update (when notification was missed)
    }
    return self;
}

- (id<DWNotificationsDataSource>)dataSource {
    return self.aggregateDataSource;
}

- (void)acceptContactRequest:(id<DWDPBasicItem>)item {
    [DWDashPayContactsActions acceptContactRequest:item completion:nil];
}

- (void)notificationsDidUpdate {
    DWNotificationsProvider *provider = [DWNotificationsProvider sharedInstance];
    [self.aggregateDataSource updateWithData:provider.data];
}

@end

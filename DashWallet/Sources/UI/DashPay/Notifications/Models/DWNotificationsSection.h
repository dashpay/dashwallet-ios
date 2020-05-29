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

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>

#import "DWNotificationDetailsConvertible.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsSection : NSObject

@property (readonly, nonatomic, assign) NSUInteger count;

- (id<DWNotificationDetails>)notificationDetailsAtIndex:(NSInteger)index;

- (instancetype)initWithIncomingFRC:(NSFetchedResultsController /* <id<DWNotificationDetailsConvertible>> */ *)incomingFRC
                         ignoredFRC:(NSFetchedResultsController /* <id<DWNotificationDetailsConvertible>> */ *)ignoredFRC
                        contactsFRC:(NSFetchedResultsController /* <id<DWNotificationDetailsConvertible>> */ *)contactsFRC;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DSReachabilityManager;

/*
 Either same as DSTransactionManagerSyncFinishedNotification or `[DWEnvironment sharedInstance].currentChainManager.syncProgress == 1`
 */
extern NSString *const DWSyncFinishedNotification;

typedef NS_ENUM(NSUInteger, DWSyncModelState) {
    DWSyncModelState_Syncing,
    DWSyncModelState_SyncDone,
    DWSyncModelState_SyncFailed,
    DWSyncModelState_NoConnection,
};

@interface DWSyncModel : NSObject

@property (readonly, nonatomic, assign) DWSyncModelState state;
@property (readonly, nonatomic, assign) float progress;

- (instancetype)initWithReachability:(DSReachabilityManager *)reachability;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

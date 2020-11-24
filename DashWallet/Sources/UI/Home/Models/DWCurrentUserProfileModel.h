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

#import <Foundation/Foundation.h>

#import "DWDPUpdateProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

@class DSBlockchainIdentity;

typedef NS_ENUM(NSUInteger, DWCurrentUserProfileModelState) {
    DWCurrentUserProfileModel_None,
    DWCurrentUserProfileModel_Loading,
    DWCurrentUserProfileModel_Done,
    DWCurrentUserProfileModel_Error,
};

@interface DWCurrentUserProfileModel : NSObject

@property (readonly, nonatomic, strong) DWDPUpdateProfileModel *updateModel;

@property (readonly, nonatomic, assign) DWCurrentUserProfileModelState state;
@property (readonly, nullable, nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;

- (void)update;

@end

NS_ASSUME_NONNULL_END

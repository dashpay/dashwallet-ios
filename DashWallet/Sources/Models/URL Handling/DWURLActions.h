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

@interface DWURLAction : NSObject
@end

//

@interface DWURLUpholdAction : DWURLAction

@property (nonatomic, strong) NSURL *url;

@end

//

@interface DWURLScanQRAction : DWURLAction
@end

//

typedef NS_ENUM(NSUInteger, DWURLRequestActionType) {
    DWURLRequestActionType_Unknown,
    DWURLRequestActionType_MasterPublicKey,
    DWURLRequestActionType_Address,
};

@interface DWURLRequestAction : DWURLAction

@property (readonly, nonatomic, assign) DWURLRequestActionType type;
@property (nonatomic, copy) NSString *sender;
@property (nonatomic, copy) NSString *request;

@end

//

@interface DWURLPayAction : DWURLAction

@property (nonatomic, strong) NSURL *paymentURL;

@end

NS_ASSUME_NONNULL_END

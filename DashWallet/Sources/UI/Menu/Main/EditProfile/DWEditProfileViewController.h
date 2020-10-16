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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DSBlockchainIdentity;
@class DWEditProfileViewController;

@protocol DWEditProfileViewControllerDelegate <NSObject>

- (void)editProfileViewControllerDidUpdate:(DWEditProfileViewController *)controller;

@end

@interface DWEditProfileViewController : UITableViewController

@property (nullable, nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;

@property (readonly, nonatomic, copy) NSString *displayName;
@property (readonly, nonatomic, copy) NSString *aboutMe;
@property (readonly, nonatomic, assign, getter=isValid) BOOL valid;

@property (nullable, nonatomic, weak) id<DWEditProfileViewControllerDelegate> delegate;

- (void)updateDisplayName:(NSString *)displayName aboutMe:(NSString *)aboutMe;

@end

NS_ASSUME_NONNULL_END

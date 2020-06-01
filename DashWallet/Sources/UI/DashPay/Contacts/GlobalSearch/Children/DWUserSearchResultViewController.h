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

#import "DWDPBasicItem.h"

NS_ASSUME_NONNULL_BEGIN

@protocol DWUserDetailsCellDelegate;
@class DWUserSearchResultViewController;

@protocol DWUserSearchResultViewControllerDelegate <NSObject>

- (void)userSearchResultViewController:(DWUserSearchResultViewController *)controller
                willDisplayItemAtIndex:(NSInteger)index;
- (void)userSearchResultViewController:(DWUserSearchResultViewController *)controller
                  didSelectItemAtIndex:(NSInteger)index
                                  cell:(UITableViewCell *)cell;

- (void)userSearchResultViewController:(DWUserSearchResultViewController *)controller
                  acceptContactRequest:(id<DWDPBasicItem>)item;
- (void)userSearchResultViewController:(DWUserSearchResultViewController *)controller
                 declineContactRequest:(id<DWDPBasicItem>)item;

@end

@interface DWUserSearchResultViewController : UITableViewController

@property (nullable, nonatomic, copy) NSString *searchQuery;
@property (nullable, nonatomic, copy) NSArray<id<DWDPBasicItem>> *items;
@property (nullable, nonatomic, weak) id<DWUserSearchResultViewControllerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END

//  
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

@class DWExploreWhereToSpendSearchCell;

@protocol DWExploreWhereToSpendSearchCellDelegate <UIBarPositioningDelegate>

@optional

- (void)searchCell:(DWExploreWhereToSpendSearchCell *)searchCell shouldStartSearchWithQuery:(NSString *)query;
- (void)searchCellDidEndSearching:(DWExploreWhereToSpendSearchCell *)searchCell;
@end

@interface DWExploreWhereToSpendSearchCell : UITableViewCell
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nullable,nonatomic,weak) id<DWExploreWhereToSpendSearchCellDelegate> delegate;

-(void)resetSearchBar;
@end

NS_ASSUME_NONNULL_END

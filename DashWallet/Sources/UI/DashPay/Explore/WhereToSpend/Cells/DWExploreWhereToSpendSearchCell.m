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

#import "DWExploreWhereToSpendSearchCell.h"

@interface DWExploreWhereToSpendSearchCell ()

@end

@implementation DWExploreWhereToSpendSearchCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self configureHierarchy];
    }
    return self;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self configureHierarchy];
    }
    
    return self;
}

-(void)configureHierarchy {
    self.searchBar = [[UISearchBar alloc] init];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    [self.contentView addSubview:_searchBar];
    
    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        //[segmentedControl.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:9],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-9]
    ]];
}
@end

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

static NSTimeInterval SEARCH_DEBOUNCE_DELAY = 0.4;

@interface DWExploreWhereToSpendSearchCell () <UISearchBarDelegate>
@property (nonatomic, strong) NSString *query;
@property (nonatomic, assign) BOOL didTapDeleteButton;
@end

@implementation DWExploreWhereToSpendSearchCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
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

-(void)resetSearchBar {
    _searchBar.text = @"";
}

-(void)configureHierarchy {
    self.searchBar = [[UISearchBar alloc] init];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    [self.contentView addSubview:_searchBar];
    
    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:9],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-9]
    ]];
}


- (void)searchWithQuery:(NSString *)searchQuery {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performSearch) object:nil];
    
    self.query = searchQuery;
    
    [self performSelector:@selector(performSearch) withObject:nil afterDelay:SEARCH_DEBOUNCE_DELAY];
}

- (void)performSearch {
    [self.delegate searchCell:self shouldStartSearchWithQuery:self.query];
}

#pragma mark UISearchBarDelegate

- (BOOL)searchBar:(UISearchBar *)searchBar shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    _didTapDeleteButton = text.length == 0;
    return YES;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if(!_didTapDeleteButton && searchText.length == 0) {
        [searchBar resignFirstResponder];
        [self.delegate searchCellDidEndSearching: self];
        return;
    }
    
    _didTapDeleteButton = false;
    
    
    [self searchWithQuery: searchText];
}


@end


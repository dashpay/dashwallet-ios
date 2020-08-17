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

#import "DWFrequentContactsDataSource.h"

#import "DWContactsModel.h"

@interface DWFrequentContactsDataSource () <DWContactsModelDelegate>

@property (nonatomic, strong) DWContactsModel *model;

@property (nonatomic, copy) NSArray<id<DWDPBasicUserItem>> *items;

@end

@implementation DWFrequentContactsDataSource

- (instancetype)init {
    self = [super init];
    if (self) {
        _model = [[DWContactsModel alloc] init];
        _model.delegate = self;
        [_model start];

        [self updateItems];
    }
    return self;
}

- (void)contactsModelDidUpdate:(nonnull DWBaseContactsModel *)model {
    [self updateItems];
}

- (void)updateItems {
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < _model.dataSource.contactsCount; i++) {
        id<DWDPBasicUserItem> item = [_model.dataSource itemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:1]];
        [items addObject:item];
    }
    _items = [items copy];
}

@end

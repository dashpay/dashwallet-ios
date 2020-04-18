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

#import "DWUserSearchModel.h"

#import "DWContactObject.h"
#import "DWEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserSearchRequest : NSObject

@property (readonly, nonatomic, copy) NSString *trimmedQuery;
@property (nonatomic, assign) uint32_t offset;
@property (nullable, nonatomic, copy) NSArray<id<DWContactItem>> *items;
@property (nonatomic, assign) BOOL requestInProgress;
@property (nonatomic, assign) BOOL hasNextPage;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserSearchRequest

- (instancetype)initWithTrimmedQuery:(NSString *)trimmedQuery {
    self = [super init];
    if (self) {
        _trimmedQuery = [trimmedQuery copy];
        _offset = 0;
    }
    return self;
}

@end

#pragma mark - Model

NS_ASSUME_NONNULL_BEGIN

static uint32_t const LIMIT = 100;
static NSTimeInterval SEARCH_DEBOUNCE_DELAY = 0.25;

@interface DWUserSearchModel ()

@property (nullable, nonatomic, strong) DWUserSearchRequest *searchRequest;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserSearchModel

- (NSString *)trimmedQuery {
    return self.searchRequest.trimmedQuery ?: @"";
}

- (void)searchWithQuery:(NSString *)searchQuery {
    NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
    NSString *trimmedQuery = [searchQuery stringByTrimmingCharactersInSet:whitespaces] ?: @"";
    if ([self.searchRequest.trimmedQuery isEqualToString:trimmedQuery]) {
        return;
    }
    self.searchRequest = [[DWUserSearchRequest alloc] initWithTrimmedQuery:trimmedQuery];

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performSearch) object:nil];
    [self performSelector:@selector(performSearch) withObject:nil afterDelay:SEARCH_DEBOUNCE_DELAY];
}

- (void)willDisplayItemAtIndex:(NSInteger)index {
    const BOOL shouldRequestNextPage = self.searchRequest.items.count >= LIMIT && index >= self.searchRequest.items.count - LIMIT / 4;
    if (shouldRequestNextPage && self.searchRequest.hasNextPage) {
        self.searchRequest.offset += LIMIT;
        [self performSearch];
    }
}

#pragma mark Private

- (void)performSearch {
    [self performSearchWithQuery:self.searchRequest.trimmedQuery offset:self.searchRequest.offset];
}

- (void)performSearchWithQuery:(NSString *)query offset:(uint32_t)offset {
    if (query.length == 0) {
        return;
    }

    self.searchRequest.requestInProgress = YES;

    DSIdentitiesManager *manager = [DWEnvironment sharedInstance].currentChainManager.identitiesManager;
    __weak typeof(self) weakSelf = self;
    [manager
        searchIdentitiesByNamePrefix:query
                              offset:offset
                               limit:LIMIT
                      withCompletion:^(NSArray<DSBlockchainIdentity *> *_Nullable blockchainIdentities, NSError *_Nullable error) {
                          __strong typeof(weakSelf) strongSelf = weakSelf;
                          if (!strongSelf) {
                              return;
                          }

                          NSAssert([NSThread isMainThread], @"Main thread is assumed here");

                          // search query was changed before results arrive, ignore results
                          if (!strongSelf.searchRequest || ![strongSelf.searchRequest.trimmedQuery isEqualToString:query]) {
                              return;
                          }

                          strongSelf.searchRequest.requestInProgress = NO;

                          if (error) {
                              strongSelf.searchRequest.hasNextPage = NO;
                              [strongSelf.delegate userSearchModel:strongSelf completedWithError:error];
                          }
                          else {
                              NSMutableArray<id<DWContactItem>> *items = strongSelf.searchRequest.items ? [strongSelf.searchRequest.items mutableCopy] : [NSMutableArray array];
                              for (DSBlockchainIdentity *blockchainIdentity in blockchainIdentities) {
                                  DWContactObject *contact = [[DWContactObject alloc] initWithBlockchainIdentity:blockchainIdentity];
                                  [items addObject:contact];
                              }

                              strongSelf.searchRequest.hasNextPage = blockchainIdentities.count >= LIMIT;
                              strongSelf.searchRequest.items = items;
                              [strongSelf.delegate userSearchModel:strongSelf completedWithItems:items];
                          }
                      }];
}

@end

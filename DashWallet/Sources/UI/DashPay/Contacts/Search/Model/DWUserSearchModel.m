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
#import "DWDashPayConstants.h"
#import "DWEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserSearchRequest : NSObject

@property (readonly, nonatomic, copy) NSString *trimmedQuery;
@property (nonatomic, assign) uint32_t offset;
@property (nullable, nonatomic, copy) NSArray<DWContactObject *> *items;
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
static NSTimeInterval SEARCH_DEBOUNCE_DELAY = 0.4;

@interface DWUserSearchModel ()

@property (nullable, nonatomic, strong) DWUserSearchRequest *searchRequest;
@property (nullable, nonatomic, strong) id<DSDAPINetworkServiceRequest> request;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserSearchModel

- (NSString *)trimmedQuery {
    return self.searchRequest.trimmedQuery ?: @"";
}

- (void)searchWithQuery:(NSString *)searchQuery {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performInitialSearch) object:nil];

    [self.request cancel];
    self.request = nil;

    self.searchRequest = nil;

    NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
    NSString *trimmedQuery = [searchQuery stringByTrimmingCharactersInSet:whitespaces] ?: @"";
    if ([self.searchRequest.trimmedQuery isEqualToString:trimmedQuery]) {
        return;
    }
    if (trimmedQuery.length < DW_MIN_USERNAME_LENGTH) {
        return;
    }

    self.searchRequest = [[DWUserSearchRequest alloc] initWithTrimmedQuery:trimmedQuery];

    [self performSelector:@selector(performInitialSearch) withObject:nil afterDelay:SEARCH_DEBOUNCE_DELAY];
}

- (void)willDisplayItemAtIndex:(NSInteger)index {
    const BOOL shouldRequestNextPage = self.searchRequest.items.count >= LIMIT && index >= self.searchRequest.items.count - LIMIT / 4;
    if (shouldRequestNextPage && self.searchRequest.hasNextPage && !self.searchRequest.requestInProgress) {
        self.searchRequest.offset += LIMIT;
        [self performSearchAndNotify:NO];
    }
}

- (DSBlockchainIdentity *)blokchainIdentityAtIndex:(NSInteger)index {
    if (index < 0 || self.searchRequest.items.count < index) {
        NSAssert(NO, @"No blockchain identity for invalid index %ld", index);
        return nil;
    }

    DWContactObject *contactObject = self.searchRequest.items[index];
    return contactObject.blockchainIdentity;
}

#pragma mark Private

- (void)performInitialSearch {
    [self performSearchAndNotify:YES];
}

- (void)performSearchAndNotify:(BOOL)notify {
    if (notify) {
        [self.delegate userSearchModelDidStartSearch:self];
    }

    if (self.searchRequest) {
        [self performSearchWithQuery:self.searchRequest.trimmedQuery offset:self.searchRequest.offset];
    }
}

- (void)performSearchWithQuery:(NSString *)query offset:(uint32_t)offset {
    self.searchRequest.requestInProgress = YES;

    DSIdentitiesManager *manager = [DWEnvironment sharedInstance].currentChainManager.identitiesManager;
    __weak typeof(self) weakSelf = self;
    self.request = [manager
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
                              NSMutableArray<DWContactObject *> *items = strongSelf.searchRequest.items ? [strongSelf.searchRequest.items mutableCopy] : [NSMutableArray array];
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

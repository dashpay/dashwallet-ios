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

#import "DWDPSearchItemsFactory.h"
#import "DWDashPayConstants.h"
#import "DWDashPayContactsActions.h"
#import "DWEnvironment.h"

#if __has_include("dashpay-Swift.h")
#import "dashpay-Swift.h"
#elif __has_include("dashwallet-Swift.h")
#import "dashwallet-Swift.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface DWUserSearchRequest : NSObject

@property (readonly, nonatomic, copy) NSString *trimmedQuery;
@property (nonatomic, assign) uint32_t offset;
@property (nullable, nonatomic, copy) NSArray<id<DWDPBasicUserItem, DWDPBlockchainIdentityBackedItem>> *items;
@property (nonatomic, assign) BOOL requestInProgress;
@property (nonatomic, assign) BOOL hasNextPage;
@property (nullable, nonatomic, copy) NSData *lastItem;


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
@property (readonly, nonatomic, strong) DWDPSearchItemsFactory *itemsFactory;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserSearchModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _itemsFactory = [[DWDPSearchItemsFactory alloc] init];
    }
    return self;
}

- (NSString *)trimmedQuery {
    return self.searchRequest.trimmedQuery ?: @"";
}

- (void)searchWithQuery:(NSString *)searchQuery {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performInitialSearch) object:nil];

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

- (id<DWDPBasicUserItem>)itemAtIndex:(NSInteger)index {
    if (index < 0 || self.searchRequest.items.count < index) {
        NSAssert(NO, @"No blockchain identity for invalid index %ld", index);
        return nil;
    }

    return self.searchRequest.items[index];
}

- (BOOL)canOpenBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    PlatformService *platform = [DWEnvironment sharedInstance].platformService;
    if (!platform.isRegistered) {
        return YES;
    }
    // Don't allow opening own profile from search
    NSString *currentUsername = platform.currentUsername;
    return currentUsername == nil || ![currentUsername isEqualToString:blockchainIdentity.currentDashpayUsername];
}

- (void)acceptContactRequest:(id<DWDPBasicUserItem>)item {
    __weak typeof(self) weakSelf = self;
    [DWDashPayContactsActions
        acceptContactRequest:item
                     context:self.context
                  completion:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
                      __strong typeof(weakSelf) strongSelf = weakSelf;
                      if (!strongSelf) {
                          return;
                      }

                      // TODO: DP update state more gently
                      [strongSelf performSearchAndNotify:YES];
                  }];
}

- (void)declineContactRequest:(id<DWDPBasicUserItem>)item {
    [DWDashPayContactsActions declineContactRequest:item context:self.context completion:nil];
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

    PlatformService *platform = [DWEnvironment sharedInstance].platformService;
    __weak typeof(self) weakSelf = self;
    [platform searchUsersWithPrefix:query
                         completion:^(NSArray<DWPlatformUser *> *users, NSError *error) {
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
                             if (!error) {
                                 NSMutableArray<id<DWDPBasicUserItem, DWDPBlockchainIdentityBackedItem>> *items = strongSelf.searchRequest.items ? [strongSelf.searchRequest.items mutableCopy] : [NSMutableArray array];
                                 for (DWPlatformUser *user in users) {
                                     id<DWDPBasicUserItem, DWDPBlockchainIdentityBackedItem> item = [strongSelf.itemsFactory itemForPlatformUser:user];
                                     [items addObject:item];
                                 }
                                 strongSelf.searchRequest.hasNextPage = users.count >= LIMIT;
                                 strongSelf.searchRequest.items = items;
                                 [strongSelf.delegate userSearchModel:strongSelf completedWithItems:items];
                             }
                             else {
                                 strongSelf.searchRequest.hasNextPage = NO;
                                 [strongSelf.delegate userSearchModel:strongSelf completedWithError:error];
                             }
                         }];
}

@end

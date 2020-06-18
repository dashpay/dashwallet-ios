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

#import "DWDashPayContactsUpdater.h"

#import "DWEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const DWDashPayContactsDidUpdateNotification = @"org.dash.wallet.dp.contacts-did-update";

static NSTimeInterval const UPDATE_INTERVAL = 30;

@interface DWDashPayContactsUpdater ()

@property (nonatomic, assign, getter=isUpdating) BOOL updating;
@property (nonatomic, assign, getter=isFetching) BOOL fetching;

@property (nullable, nonatomic, copy) void (^fetchCompletion)(BOOL success, NSArray<NSError *> *errors);

@end

NS_ASSUME_NONNULL_END

@implementation DWDashPayContactsUpdater

+ (instancetype)sharedInstance {
    static DWDashPayContactsUpdater *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (void)beginUpdating {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    if (myBlockchainIdentity == nil) {
        return;
    }

    if (self.isUpdating) {
        return;
    }
    self.updating = YES;

    [self fetch];
}

- (void)endUpdating {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    if (!self.isUpdating) {
        return;
    }
    self.updating = NO;

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchInternal) object:nil];
}

- (void)fetch {
    [self fetchIntiatedInternally:NO completion:nil];
}

- (void)fetchWithCompletion:(void (^_Nullable)(BOOL success, NSArray<NSError *> *errors))completion {
    [self fetchIntiatedInternally:NO completion:completion];
}

#pragma mark - Private

- (void)fetchInternal {
    [self fetchIntiatedInternally:YES completion:nil];
}

- (void)fetchIntiatedInternally:(BOOL)initiatedInternally completion:(void (^_Nullable)(BOOL success, NSArray<NSError *> *errors))completion {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    if (myBlockchainIdentity == nil) {
        return;
    }

    if (!initiatedInternally) {
        self.fetchCompletion = completion;
    }

    if (self.isFetching) {
        return;
    }
    self.fetching = YES;

    // Cancel any scheduled calls if fetch is called manually
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchInternal) object:nil];

    __weak typeof(self) weakSelf = self;
    [myBlockchainIdentity fetchContactRequests:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.fetching = NO;

        if (!strongSelf.isUpdating) {
            return;
        }

        DSLogVerbose(@"DWDP: Fetch contact requests %@: %@", success ? @"Succeeded" : @"Failed", errors);

        if (strongSelf.fetchCompletion) {
            strongSelf.fetchCompletion(success, errors);
            strongSelf.fetchCompletion = nil;
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:DWDashPayContactsDidUpdateNotification object:nil];

        [strongSelf performSelector:@selector(fetchInternal) withObject:nil afterDelay:UPDATE_INTERVAL];
    }];
}

@end

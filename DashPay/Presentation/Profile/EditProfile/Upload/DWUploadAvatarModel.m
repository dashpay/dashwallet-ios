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

#import "DWUploadAvatarModel.h"

#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const ImageDeleteHash = @"ImgurImageDeleteHash";

@interface DWUploadAvatarModel ()

@property (nonatomic, assign) DWUploadAvatarModelState state;

@property (nonatomic, assign) BOOL cancelled;
@property (nullable, nonatomic, copy) NSString *resultURLString;
@property (nullable, nonatomic, copy) NSString *failureMessage;
@property (nonatomic, assign) BOOL failureIsRetryable;
@property (nonatomic, strong) DWAvatarUploadClient *client;
@property (nullable, nonatomic, strong) id<DWAvatarUploadCancelling> uploadOperation;
@property (nonatomic, assign) NSUInteger attemptGeneration;

@end

NS_ASSUME_NONNULL_END

@implementation DWUploadAvatarModel

- (instancetype)initWithImage:(UIImage *)image {
    self = [super init];
    if (self) {
        _image = image;
        _client = [[DWAvatarUploadClient alloc] init];

        [self retry];
    }
    return self;
}

- (void)retry {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self retry];
        });
        return;
    }

    [self.uploadOperation cancel];
    self.attemptGeneration += 1;
    const NSUInteger generation = self.attemptGeneration;
    self.cancelled = NO;
    self.failureMessage = nil;
    self.failureIsRetryable = YES;
    self.state = DWUploadAvatarModelState_Loading;
    NSString *deleteHash = [[NSUserDefaults standardUserDefaults] stringForKey:ImageDeleteHash];

    __weak typeof(self) weakSelf = self;
    self.uploadOperation = [self.client
        uploadImage:self.image
         deleteHash:deleteHash
         completion:^(NSString *_Nullable link, NSString *_Nullable newDeleteHash, NSError *_Nullable error) {
             __strong typeof(weakSelf) strongSelf = weakSelf;
             if (!strongSelf || strongSelf.cancelled || strongSelf.attemptGeneration != generation) {
                 return;
             }

             NSAssert([NSThread isMainThread], @"Avatar state is UI-observable and must update on main");
             if (error != nil) {
                 // Missing credentials, or a host that refused the action
                 // outright: neither can succeed on a retry, so the error UI
                 // must not offer one. Everything else (rate limits, 5xx,
                 // transport) stays retryable.
                 const BOOL permanent =
                     [error.domain isEqualToString:DWAvatarUploadClient.errorDomain] &&
                     (error.code == DWAvatarUploadClient.errorCodeNotConfigured ||
                      error.code == DWAvatarUploadClient.errorCodeRefused);
                 strongSelf.failureIsRetryable = !permanent;
                 strongSelf.failureMessage = permanent ? error.localizedDescription : nil;
                 strongSelf.state = DWUploadAvatarModelState_Error;
                 return;
             }

             if (newDeleteHash.length > 0) {
                 [[NSUserDefaults standardUserDefaults] setObject:newDeleteHash forKey:ImageDeleteHash];
             }
             else {
                 [[NSUserDefaults standardUserDefaults] removeObjectForKey:ImageDeleteHash];
             }
             strongSelf.resultURLString = link;
             strongSelf.state = DWUploadAvatarModelState_Success;
         }];
}

- (void)cancel {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cancel];
        });
        return;
    }

    self.cancelled = YES;
    self.attemptGeneration += 1;
    [self.uploadOperation cancel];
}

@end

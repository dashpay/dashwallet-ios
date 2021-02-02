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

#import "DWCheckExistenceUsernameValidationRule.h"

#import "DWAllowedCharactersUsernameValidationRule.h"
#import "DWDashPayConstants.h"
#import "DWEnvironment.h"
#import "DWFirstUsernameSymbolValidationRule.h"
#import "DWLengthUsernameValidationRule.h"
#import "DWUsernameValidationRule+Protected.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval VALIDATION_DEBOUNCE_DELAY = 0.4;

@interface DWCheckExistenceUsernameValidationRule ()

@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *titleByResult;
@property (nullable, nonatomic, weak) id<DWCheckExistenceUsernameValidationRuleDelegate> delegate;

@property (nullable, nonatomic, copy) NSString *username;
@property (nullable, nonatomic, strong) id<DSDAPINetworkServiceRequest> request;
@property (readonly, nonatomic, copy) NSArray<DWUsernameValidationRule *> *validators;

@end

NS_ASSUME_NONNULL_END

@implementation DWCheckExistenceUsernameValidationRule

- (instancetype)initWithDelegate:(id<DWCheckExistenceUsernameValidationRuleDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;

        _validators = @[
            [[DWLengthUsernameValidationRule alloc] init],
            [[DWAllowedCharactersUsernameValidationRule alloc] init],
            [[DWFirstUsernameSymbolValidationRule alloc] init],
        ];

        NSMutableDictionary<NSNumber *, NSString *> *titleByResult = [NSMutableDictionary dictionary];
        titleByResult[@(DWUsernameValidationRuleResultLoading)] = NSLocalizedString(@"Validating username…", nil);
        titleByResult[@(DWUsernameValidationRuleResultValid)] = NSLocalizedString(@"Username available", nil);
        titleByResult[@(DWUsernameValidationRuleResultError)] = NSLocalizedString(@"Validating username failed", nil);
        titleByResult[@(DWUsernameValidationRuleResultInvalidCritical)] = NSLocalizedString(@"Username taken", nil);
        self.titleByResult = titleByResult;
    }
    return self;
}

- (void)setValidationResult:(DWUsernameValidationRuleResult)validationResult {
    [super setValidationResult:validationResult];

    [self.delegate checkExistenceUsernameValidationRuleDidValidate:self];
}

- (NSString *)title {
    return self.titleByResult[@(self.validationResult)];
}

- (void)validateText:(NSString *)text {
    [self.request cancel];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performValidation) object:nil];
    self.username = text;

    [self.validators makeObjectsPerformSelector:@selector(validateText:) withObject:text];

    BOOL hasInvalid = NO;
    for (DWUsernameValidationRule *rule in self.validators) {
        if (rule.validationResult == DWUsernameValidationRuleResultInvalid) {
            hasInvalid = YES;
            break;
        }
    }

    if (hasInvalid || text.length == 0) {
        self.validationResult = DWUsernameValidationRuleResultHidden;
        return;
    }

    self.validationResult = DWUsernameValidationRuleResultLoading;

    [self performSelector:@selector(performValidation) withObject:nil afterDelay:VALIDATION_DEBOUNCE_DELAY];
}

#pragma mark - Private

- (void)performValidation {
    [self performValidationWithUsername:self.username];
}

- (void)performValidationWithUsername:(NSString *)username {
    DSIdentitiesManager *manager = [DWEnvironment sharedInstance].currentChainManager.identitiesManager;
    __weak typeof(self) weakSelf = self;
    self.request = [manager
        searchIdentityByDashpayUsername:username
                         withCompletion:^(BOOL succeess, DSBlockchainIdentity *_Nullable blockchainIdentity, NSError *_Nullable error) {
                             __strong typeof(weakSelf) strongSelf = weakSelf;
                             if (!strongSelf) {
                                 return;
                             }

                             NSAssert([NSThread isMainThread], @"Main thread is assumed here");

                             // search query was changed before results arrive, ignore results
                             if (![strongSelf.username isEqualToString:username]) {
                                 return;
                             }

                             if (succeess) {
                                 if (blockchainIdentity != nil) {
                                     strongSelf.validationResult = DWUsernameValidationRuleResultInvalidCritical;
                                 }
                                 else {
                                     strongSelf.validationResult = DWUsernameValidationRuleResultValid;
                                 }
                             }
                             else {
                                 strongSelf.validationResult = DWUsernameValidationRuleResultError;
                             }
                         }];
}

@end

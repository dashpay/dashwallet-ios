//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

@class DWRecoverModel;
@class DWRecoverContentView;

@protocol DWRecoverContentViewDelegate <NSObject>

- (void)recoverContentView:(DWRecoverContentView *)view showIncorrectWord:(NSString *)incorrectWord;
- (void)recoverContentView:(DWRecoverContentView *)view
    invalidWordsCountInsteadOf:(NSInteger)neededWordsCount;
- (void)recoverContentViewBadRecoveryPhrase:(DWRecoverContentView *)view;
- (void)recoverContentViewDidRecoverWallet:(DWRecoverContentView *)view;
- (void)recoverContentViewPerformWipe:(DWRecoverContentView *)view;
- (void)recoverContentViewWipeNotAllowed:(DWRecoverContentView *)view;
- (void)recoverContentViewWipeNotAllowedPhraseMismatch:(DWRecoverContentView *)view;

@end

@interface DWRecoverContentView : UIView

@property (nonatomic, strong) DWRecoverModel *model;

@property (nonatomic, assign) CGSize visibleSize;
@property (nullable, nonatomic, copy) NSString *title;

@property (nullable, nonatomic, weak) id<DWRecoverContentViewDelegate> delegate;

- (void)activateTextView;
- (void)continueAction;

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

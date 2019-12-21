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

typedef NS_ENUM(NSUInteger, DWSeedPhraseDisplayType) {
    DWSeedPhraseDisplayType_Backup,
    DWSeedPhraseDisplayType_Preview,
};

@class DWPreviewSeedPhraseContentView;
@class DWSeedPhraseModel;

@protocol DWPreviewSeedPhraseContentViewDelegate <NSObject>

- (void)previewSeedPhraseContentView:(DWPreviewSeedPhraseContentView *)view
               didChangeConfirmation:(BOOL)confirmed;

@end

@interface DWPreviewSeedPhraseContentView : UIView

@property (nullable, nonatomic, strong) DWSeedPhraseModel *model;
@property (nonatomic, assign) DWSeedPhraseDisplayType displayType;

@property (nonatomic, assign) CGSize visibleSize;
@property (nullable, nonatomic, weak) id<DWPreviewSeedPhraseContentViewDelegate> delegate;

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)viewWillAppear;
- (void)viewDidAppear;

- (void)updateSeedPhraseModelAnimated:(DWSeedPhraseModel *)seedPhrase;
- (void)showScreenshotDetectedErrorMessage;

@end

NS_ASSUME_NONNULL_END

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

#import <Foundation/Foundation.h>

#import "DWSeedPhraseType.h"

NS_ASSUME_NONNULL_BEGIN

extern CGFloat DWInteritemSpacing(DWSeedPhraseType type);

@class DWSeedWordModel;

@interface DWSeedPhraseRow : NSObject

@property (readonly, nonatomic, strong) NSArray<DWSeedWordModel *> *wordModels;
@property (readonly, nonatomic, strong) NSArray<NSValue *> *wordSizes;

@property (readonly, nonatomic, assign) CGFloat height;
@property (readonly, nonatomic, assign) CGFloat width;

- (instancetype)initWithType:(DWSeedPhraseType)type NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)canAddWordWithSize:(CGSize)wordSize parentWidth:(CGFloat)parentWidth;
- (void)addWord:(DWSeedWordModel *)wordModel size:(CGSize)size;

@end

NS_ASSUME_NONNULL_END

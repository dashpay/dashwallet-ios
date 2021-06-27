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

#import <KVO-MVVM/KVOUICollectionViewCell.h>

#import "DWDPGenericItemView.h"

// supports displaying:
#import "DWDPBasicItem.h"
#import "DWDPRespondedRequestItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPBasicCell : KVOUICollectionViewCell

@property (readonly, class, nonatomic) Class itemViewClass;

@property (readonly, nonatomic, strong) DWDPGenericItemView *itemView;
@property (nonatomic, assign) BOOL displayItemBackgroundView;
@property (nonatomic, assign) CGFloat contentWidth;

@property (nullable, nonatomic, weak) id<DWDPItemCellDelegate> delegate;

@property (nullable, nonatomic, strong) id<DWDPBasicItem> item;
- (void)setItem:(id<DWDPBasicItem>)item highlightedText:(nullable NSString *)highlightedText NS_REQUIRES_SUPER;

- (void)reloadAttributedData;

@end

NS_ASSUME_NONNULL_END

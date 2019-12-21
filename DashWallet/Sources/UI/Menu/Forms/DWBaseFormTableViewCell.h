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

#import <KVO-MVVM/KVOUITableViewCell.h>

NS_ASSUME_NONNULL_BEGIN

extern CGFloat const DW_FORM_CELL_VERTICAL_PADDING;
extern CGFloat const DW_FORM_CELL_SPACING;

typedef NS_ENUM(NSUInteger, DWFormCellRoundMask) {
    DWFormCellRoundMask_Top = 1 << 0,
    DWFormCellRoundMask_Bottom = 1 << 1,
};

@interface DWBaseFormTableViewCell : KVOUITableViewCell

@property (readonly, nonatomic, strong) UIView *roundedContentView;
@property (nonatomic, assign) DWFormCellRoundMask roundMask;

/// Default is `YES`
- (BOOL)shouldAnimatePressWhenHighlighted;

@end

NS_ASSUME_NONNULL_END

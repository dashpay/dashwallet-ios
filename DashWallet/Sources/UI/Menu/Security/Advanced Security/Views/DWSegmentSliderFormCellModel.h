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

#import "DWBaseFormCellModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSegmentSliderFormCellModel : DWBaseFormCellModel

@property (nullable, nonatomic, copy) NSAttributedString *detail;

@property (nullable, nonatomic, copy) NSString *sliderLeftText;
@property (nullable, nonatomic, copy) NSString *sliderRightText;
@property (nullable, nonatomic, copy) NSAttributedString *sliderLeftAttributedText;
@property (nullable, nonatomic, copy) NSAttributedString *sliderRightAttributedText;

@property (nonatomic, copy) NSArray<id<NSCopying>> *sliderValues;
@property (nonatomic, assign) NSInteger selectedItemIndex;

@property (nullable, nonatomic, copy) NSAttributedString *descriptionText;

@property (nullable, copy, nonatomic) void (^didChangeValueBlock)(DWSegmentSliderFormCellModel *cellModel);

@end

NS_ASSUME_NONNULL_END

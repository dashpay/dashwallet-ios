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

#import "DWTitleDetailItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTitleDetailCellModel : NSObject <DWTitleDetailItem>

- (instancetype)initWithTitle:(nullable NSString *)title
                     userItem:(id<DWDPBasicUserItem>)userItem
                 copyableData:(nullable NSString *)copyableData;

- (instancetype)initWithStyle:(DWTitleDetailItemStyle)style plainCenteredDetail:(NSString *)plainDetail;

- (instancetype)initWithStyle:(DWTitleDetailItemStyle)style plainLeftAlignedDetail:(NSString *)plainDetail;

- (instancetype)initWithStyle:(DWTitleDetailItemStyle)style
                        title:(nullable NSString *)title
                  plainDetail:(NSString *)plainDetail;

- (instancetype)initWithStyle:(DWTitleDetailItemStyle)style
                        title:(nullable NSString *)title
             attributedDetail:(NSAttributedString *)attributedDetail;

- (instancetype)initWithStyle:(DWTitleDetailItemStyle)style
                        title:(nullable NSString *)title
             attributedDetail:(NSAttributedString *)attributedDetail
                 copyableData:(nullable NSString *)copyableData;

- (instancetype)initWithStyle:(DWTitleDetailItemStyle)style
                        title:(nullable NSString *)title
                  plainDetail:(nullable NSString *)plainDetail
             attributedDetail:(nullable NSAttributedString *)attributedDetail
                 copyableData:(nullable NSString *)copyableData
              detailAlignment:(NSTextAlignment)detailAlignment;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

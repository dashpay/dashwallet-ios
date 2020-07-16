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

#import "DWDPTxListCell.h"

#import "DWDPTxItem.h"
#import "DWDPTxItemView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPTxListCell ()

@property (readonly, nonatomic, strong) DWDPTxItemView *itemView;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPTxListCell

@dynamic itemView;

+ (Class)itemViewClass {
    return DWDPTxItemView.class;
}

- (void)reloadAttributedData {
    [super reloadAttributedData];

    id<DWDPTxItem> txItem = (id<DWDPTxItem>)self.item;
    NSAssert([txItem conformsToProtocol:@protocol(DWDPTxItem)], @"Invalid item type");
    self.itemView.amountLabel.attributedText = txItem.amountString;
}

@end

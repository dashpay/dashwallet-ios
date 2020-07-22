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

#import "DWDPTextStatusCell.h"

#import "DWDPGenericStatusItemView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPTextStatusCell ()

@property (readonly, nonatomic, strong) DWDPGenericStatusItemView *itemView;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPTextStatusCell

@dynamic itemView;

+ (Class)itemViewClass {
    return DWDPGenericStatusItemView.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        NSString *text = NSLocalizedString(@"Pending", nil);
        self.itemView.statusLabel.text = text;
    }
    return self;
}

@end

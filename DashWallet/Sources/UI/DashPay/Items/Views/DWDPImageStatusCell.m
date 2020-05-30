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

#import "DWDPImageStatusCell.h"

#import "DWDPGenericImageItemView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPImageStatusCell ()

@property (readonly, nonatomic, strong) DWDPGenericImageItemView *itemView;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPImageStatusCell

@dynamic itemView;

+ (Class)itemViewClass {
    return DWDPGenericImageItemView.class;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        UIImage *image = [UIImage imageNamed:@"dp_established_contact"];
        self.itemView.imageView.image = image;
    }
    return self;
}

@end

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

#import "DWOnboardingCollectionViewCell.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWOnboardingCollectionViewCell ()

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *detailLabel;

@end

@implementation DWOnboardingCollectionViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.titleLabel.textColor = [UIColor dw_lightTitleColor];
    self.detailLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    self.detailLabel.textColor = [UIColor dw_lightTitleColor];
}

- (void)setModel:(nullable id<DWOnboardingPageProtocol>)model {
    _model = model;

    self.titleLabel.text = model.title;
    self.detailLabel.text = model.detail;
}

@end

NS_ASSUME_NONNULL_END

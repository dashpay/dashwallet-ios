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

#import "DWBackupInfoHeaderView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat DescriptionBottomPadding(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 28.0;
    }
    else {
        return 56.0;
    }
}

@interface DWBackupInfoHeaderView ()

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *descriptionBottomPadding;

@end

@implementation DWBackupInfoHeaderView

- (void)awakeFromNib {
    [super awakeFromNib];

    self.descriptionBottomPadding.constant = DescriptionBottomPadding();

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];

    self.titleLabel.text = NSLocalizedString(@"It's Important", nil);
    self.descriptionLabel.text = NSLocalizedString(@"We are about to show you the secret key to your wallet.", nil);
}

@end

NS_ASSUME_NONNULL_END

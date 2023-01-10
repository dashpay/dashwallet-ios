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

#import "DWPayTableViewCell.h"

#import "DWPayOptionModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN


static CGFloat const MAX_ALLOWED_BUTTON_WIDTH = 108.0;

@interface DWPayTableViewCell ()

@property (strong, nonatomic) IBOutlet UIImageView *iconImageView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UIButton *actionButton;

@end

@implementation DWPayTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
}

- (void)setModel:(nullable DWPayOptionModel *)model {
    _model = model;

    DWPayOptionModelType type = model.type;
    self.titleLabel.text = model.title;
    self.iconImageView.image = model.icon;

    [self.actionButton setTitle:model.actionTitle forState:UIControlStateNormal];
    [self.actionButton sizeToFit];

    [self updateDetails];
}

#pragma mark - Actions

- (IBAction)actionButtonAction:(UIButton *)sender {
    [self.delegate payTableViewCell:self action:sender];
}

#pragma mark - Private

- (void)updateDetails {
    self.descriptionLabel.text = self.model.details;
    self.descriptionLabel.textColor = self.model.descriptionColor;
    self.actionButton.enabled = YES;

#if SNAPSHOT
    DWPayOptionModelType type = _model.type;

    if (type == DWPayOptionModelType_Pasteboard) {
        self.actionButton.accessibilityIdentifier = @"send_pasteboard_button";
    }
#endif /* SNAPSHOT */
}

@end

NS_ASSUME_NONNULL_END

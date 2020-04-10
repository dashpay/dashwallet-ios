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

#import "DWDPRegistrationErrorTableViewCell.h"

#import "DWDPRegistrationStatus.h"
#import "DWProgressView.h"
#import "DWUIKit.h"


@interface DWDPImageTitleButton : UIButton
@end

@implementation DWDPImageTitleButton

- (CGSize)intrinsicContentSize {
    CGSize s = [super intrinsicContentSize];

    return CGSizeMake(s.width + self.titleEdgeInsets.left + self.titleEdgeInsets.right,
                      s.height + self.titleEdgeInsets.top + self.titleEdgeInsets.bottom);
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface DWDPRegistrationErrorTableViewCell ()

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (weak, nonatomic) IBOutlet DWProgressView *progressView;
@property (weak, nonatomic) IBOutlet UIButton *retryButton;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPRegistrationErrorTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    self.titleLabel.text = NSLocalizedString(@"Error Upgrading", nil);
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];

    self.retryButton.tintColor = [UIColor dw_dashBlueColor];
    self.retryButton.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
}

- (void)setStatus:(DWDPRegistrationStatus *)status {
    _status = status;

    self.descriptionLabel.text = [status stateDescription];
    [self.progressView setProgress:[status progress] animated:YES];
}

- (IBAction)retryButtonAction:(id)sender {
    [self.delegate registrationErrorRetryAction];
}

@end

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

#import "DWDPRegistrationStatusTableViewCell.h"

#import "DWDPRegistrationStatus.h"
#import "DWDashPayAnimationView.h"
#import "DWProgressView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPRegistrationStatusTableViewCell ()

@property (weak, nonatomic) IBOutlet DWDashPayAnimationView *animationView;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (weak, nonatomic) IBOutlet DWProgressView *progressView;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPRegistrationStatusTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    self.titleLabel.text = NSLocalizedString(@"Upgrading to DashPay", nil);
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)setStatus:(DWDPRegistrationStatus *)status {
    _status = status;

    self.descriptionLabel.text = [status stateDescription];
    [self.progressView setProgress:[status progress] animated:YES];
}

- (void)willMoveToWindow:(nullable UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];

    if (newWindow == nil) {
        [self.animationView stopAnimating];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];

    if (self.window) {
        [self.animationView startAnimating];
    }
}

@end

//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWInvitationActionsView.h"

#import "DWActionButton.h"
#import "DWTextField.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWInvitationActionsView () <UITextFieldDelegate>

@end

NS_ASSUME_NONNULL_END

@implementation DWInvitationActionsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.textColor = [UIColor dw_darkTitleColor];
        title.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        title.text = NSLocalizedString(@"Tag for your reference", nil);
        title.adjustsFontForContentSizeCategory = YES;
        title.numberOfLines = 0;
        [self addSubview:title];

        DWTextField *textField = [[DWTextField alloc] init];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.horizontalPadding = 16.0;
        textField.verticalPadding = 8;
        textField.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        textField.textColor = [UIColor dw_darkTitleColor];
        textField.returnKeyType = UIReturnKeyDone;
        textField.delegate = self;
        textField.backgroundColor = [UIColor dw_backgroundColor];
        textField.layer.cornerRadius = 8;
        textField.layer.masksToBounds = YES;
        textField.placeholder = NSLocalizedString(@"eg: Dad", @"Invitation tag placeholder");
        [self addSubview:textField];

        DWActionButton *copyButton = [[DWActionButton alloc] init];
        copyButton.translatesAutoresizingMaskIntoConstraints = NO;
        copyButton.inverted = YES;
        [copyButton addTarget:self action:@selector(copyButtonAction) forControlEvents:UIControlEventTouchUpInside];
        [copyButton setTitle:NSLocalizedString(@"Copy Invitation Link", nil) forState:UIControlStateNormal];
        [copyButton setImage:[[UIImage imageNamed:@"invitation_copy"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                    forState:UIControlStateNormal];
        [copyButton setInsetsForContentPadding:UIEdgeInsetsMake(0, 20, 0, 20) imageTitlePadding:10];
        [self addSubview:copyButton];

        [NSLayoutConstraint activateConstraints:@[
            [title.topAnchor constraintEqualToAnchor:self.topAnchor],
            [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

            [textField.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                                constant:12],
            [textField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:textField.trailingAnchor],
            [textField.heightAnchor constraintEqualToConstant:52],

            [copyButton.topAnchor constraintEqualToAnchor:textField.bottomAnchor
                                                 constant:8],
            [copyButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:copyButton.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:copyButton.bottomAnchor],
            [copyButton.heightAnchor constraintEqualToConstant:44],
        ]];
    }
    return self;
}

- (void)copyButtonAction {
    [self.delegate invitationActionsViewCopyButtonAction:self];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate invitationActionsView:self didChangeTag:textField.text ?: @""];
    });
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

//
//  Created by Sam Westrich
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

#import "DWSignPayloadView.h"
#import "DWUIKit.h"

CGFloat const DW_SIGNED_PAYLOAD_TOP_PADDING = 12.0;
CGFloat const DW_SIGNED_PAYLOAD_INTER_PADDING = 12.0;
CGFloat const DW_SIGNED_PAYLOAD_BOTTOM_PADDING = 12.0;

@interface DWSignPayloadView ()

@property (nonatomic, strong) UITextView *messageToSignTextView;
@property (nonatomic, strong) UITextView *signedMessageInputTextView;

@end


@implementation DWSignPayloadView


- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];
        UITextView *messageToSignTextView = [[UITextView alloc] initWithFrame:CGRectZero];
        messageToSignTextView.translatesAutoresizingMaskIntoConstraints = NO;
        messageToSignTextView.backgroundColor = [UIColor dw_backgroundColor];
        messageToSignTextView.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        [self addSubview:messageToSignTextView];
        _messageToSignTextView = messageToSignTextView;

        UITextView *signedMessageInputTextView = [[UITextView alloc] initWithFrame:CGRectZero];
        signedMessageInputTextView.translatesAutoresizingMaskIntoConstraints = NO;
        signedMessageInputTextView.delegate = self;
        [self addSubview:signedMessageInputTextView];
        _signedMessageInputTextView = signedMessageInputTextView;

        [NSLayoutConstraint activateConstraints:@[
            [messageToSignTextView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                            constant:DW_SIGNED_PAYLOAD_TOP_PADDING],
            [messageToSignTextView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [messageToSignTextView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [messageToSignTextView.heightAnchor constraintEqualToAnchor:signedMessageInputTextView.heightAnchor
                                                             multiplier:0.67
                                                               constant:0],

            [signedMessageInputTextView.topAnchor constraintEqualToAnchor:messageToSignTextView.bottomAnchor
                                                                 constant:DW_SIGNED_PAYLOAD_INTER_PADDING],
            [signedMessageInputTextView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [signedMessageInputTextView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [signedMessageInputTextView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                                    constant:-DW_SIGNED_PAYLOAD_BOTTOM_PADDING],
        ]];
    }
    return self;
}

- (void)setModel:(DWSignPayloadModel *)model {
    _model = model;
    [self.messageToSignTextView setText:[NSString stringWithFormat:@"signmessage %@ %@", model.collateralAddress, model.payloadCollateralString]];
}

- (BOOL)resignFirstResponder {
    BOOL resigned = [super resignFirstResponder];
    resigned |= [self.signedMessageInputTextView resignFirstResponder];
    return resigned;
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    if (textView == self.signedMessageInputTextView) {
        self.model.unverifiedSignatureString = textView.text;
    }
}

@end

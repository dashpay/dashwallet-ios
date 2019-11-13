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
@property (nonatomic, strong) UILabel *instructionForCopyingLabel;
@property (nonatomic, strong) UILabel *instructionForPastingLabel;

@end


@implementation DWSignPayloadView


- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UILabel *instructionForCopyingLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        instructionForCopyingLabel.translatesAutoresizingMaskIntoConstraints = NO;
        instructionForCopyingLabel.backgroundColor = [UIColor dw_backgroundColor];
        instructionForCopyingLabel.layer.cornerRadius = 3;
        instructionForCopyingLabel.lineBreakMode = NSLineBreakByWordWrapping;
        instructionForCopyingLabel.numberOfLines = 4;
        instructionForCopyingLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];

        [self addSubview:instructionForCopyingLabel];
        _instructionForCopyingLabel = instructionForCopyingLabel;


        UITextView *messageToSignTextView = [[UITextView alloc] initWithFrame:CGRectZero];
        messageToSignTextView.translatesAutoresizingMaskIntoConstraints = NO;
        messageToSignTextView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        messageToSignTextView.layer.cornerRadius = 3;
        messageToSignTextView.textContainer.lineBreakMode = NSLineBreakByCharWrapping;
        messageToSignTextView.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        [self addSubview:messageToSignTextView];
        _messageToSignTextView = messageToSignTextView;

        UILabel *instructionForPastingLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        instructionForPastingLabel.translatesAutoresizingMaskIntoConstraints = NO;
        instructionForPastingLabel.backgroundColor = [UIColor dw_backgroundColor];
        instructionForPastingLabel.lineBreakMode = NSLineBreakByWordWrapping;
        instructionForPastingLabel.numberOfLines = 4;
        instructionForPastingLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];

        [self addSubview:instructionForPastingLabel];
        _instructionForPastingLabel = instructionForPastingLabel;

        UITextView *signedMessageInputTextView = [[UITextView alloc] initWithFrame:CGRectZero];
        signedMessageInputTextView.translatesAutoresizingMaskIntoConstraints = NO;
        signedMessageInputTextView.textContainer.lineBreakMode = NSLineBreakByCharWrapping;
        signedMessageInputTextView.delegate = self;
        signedMessageInputTextView.backgroundColor = [UIColor whiteColor];
        signedMessageInputTextView.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        [self addSubview:signedMessageInputTextView];
        _signedMessageInputTextView = signedMessageInputTextView;

        [NSLayoutConstraint activateConstraints:@[

            [instructionForCopyingLabel.topAnchor constraintEqualToAnchor:self.topAnchor
                                                                 constant:DW_SIGNED_PAYLOAD_TOP_PADDING],
            [instructionForCopyingLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [instructionForCopyingLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [instructionForCopyingLabel.heightAnchor constraintEqualToAnchor:messageToSignTextView.heightAnchor
                                                                  multiplier:0.5
                                                                    constant:0],

            [messageToSignTextView.topAnchor constraintEqualToAnchor:instructionForCopyingLabel.bottomAnchor
                                                            constant:DW_SIGNED_PAYLOAD_INTER_PADDING],
            [messageToSignTextView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [messageToSignTextView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [messageToSignTextView.heightAnchor constraintEqualToAnchor:signedMessageInputTextView.heightAnchor
                                                             multiplier:0.67
                                                               constant:0],

            [instructionForPastingLabel.topAnchor constraintEqualToAnchor:messageToSignTextView.bottomAnchor
                                                                 constant:DW_SIGNED_PAYLOAD_INTER_PADDING],

            [instructionForPastingLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [instructionForPastingLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [instructionForPastingLabel.heightAnchor constraintEqualToAnchor:signedMessageInputTextView.heightAnchor
                                                                  multiplier:0.33
                                                                    constant:0],

            [signedMessageInputTextView.topAnchor constraintEqualToAnchor:instructionForPastingLabel.bottomAnchor
                                                                 constant:DW_SIGNED_PAYLOAD_INTER_PADDING],
            [signedMessageInputTextView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [signedMessageInputTextView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [signedMessageInputTextView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                                    constant:DW_SIGNED_PAYLOAD_BOTTOM_PADDING],
        ]];
    }
    return self;
}

- (void)setModel:(DWSignPayloadModel *)model {
    _model = model;
    self.messageToSignTextView.text = [NSString stringWithFormat:@"%@ %@", model.collateralAddress, model.payloadCollateralString];
    self.instructionForCopyingLabel.text = model.instructionStringForCopying;
    self.instructionForPastingLabel.text = model.instructionStringForPasting;
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

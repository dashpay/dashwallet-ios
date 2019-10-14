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

#import "DWSyncView.h"

#import "DWProgressView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSyncView ()

@property (weak, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UIView *roundedView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UILabel *percentLabel;
@property (strong, nonatomic) IBOutlet UIButton *retryButton;
@property (strong, nonatomic) IBOutlet DWProgressView *progressView;
@property (assign, nonatomic) BOOL viewStateSeeingBlocks;
@property (assign, nonatomic) DWSyncModelState syncState;

@end

@implementation DWSyncView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil];
    [self addSubview:self.contentView];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.widthAnchor],
    ]];

    self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    self.percentLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle1];
    self.viewStateSeeingBlocks = NO;

    UITapGestureRecognizer *tapGestureRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(changeSeeBlocksStateAction:)];
    [self.roundedView addGestureRecognizer:tapGestureRecognizer];
}

- (void)setSyncState:(DWSyncModelState)state {
    _syncState = state;
    if (state == DWSyncModelState_NoConnection) {
        self.titleLabel.textColor = [UIColor dw_lightTitleColor];
        self.descriptionLabel.textColor = [UIColor dw_lightTitleColor];
    }
    else {
        self.titleLabel.textColor = [UIColor dw_secondaryTextColor];
        self.descriptionLabel.textColor = [UIColor dw_quaternaryTextColor];
    }

    switch (state) {
        case DWSyncModelState_Syncing:
        case DWSyncModelState_SyncDone: {
            self.roundedView.backgroundColor = [UIColor dw_backgroundColor];
            self.percentLabel.hidden = NO;
            self.retryButton.hidden = YES;
            self.progressView.hidden = NO;
            self.titleLabel.text = NSLocalizedString(@"Syncing", nil);
            [self updateUIForViewStateSeeingBlocks];
            break;
        }
        case DWSyncModelState_SyncFailed: {
            self.roundedView.backgroundColor = [UIColor dw_backgroundColor];
            self.percentLabel.hidden = YES;
            self.retryButton.tintColor = [UIColor dw_redColor];
            self.retryButton.hidden = NO;
            self.progressView.hidden = NO;
            self.titleLabel.text = NSLocalizedString(@"Sync Failed", nil);
            self.descriptionLabel.text = NSLocalizedString(@"Please try again", nil);

            break;
        }
        case DWSyncModelState_NoConnection: {
            self.roundedView.backgroundColor = [UIColor dw_redColor];
            self.percentLabel.hidden = YES;
            self.retryButton.tintColor = [UIColor dw_backgroundColor];
            self.retryButton.hidden = NO;
            self.progressView.hidden = YES;
            self.titleLabel.text = NSLocalizedString(@"Unable to connect", nil);
            self.descriptionLabel.text = NSLocalizedString(@"Check your connection", nil);

            break;
        }
    }
}

- (void)setProgress:(float)progress animated:(BOOL)animated {
    self.percentLabel.text = [NSString stringWithFormat:@"%0.1f%%", progress * 100.0];
    [self.progressView setProgress:progress animated:animated];
    if (self.viewStateSeeingBlocks && self.syncState == DWSyncModelState_Syncing) {
        [self updateUIForViewStateSeeingBlocks];
    }
}

- (void)updateUIForViewStateSeeingBlocks {
    if (self.syncState == DWSyncModelState_Syncing || self.syncState == DWSyncModelState_SyncDone) {
        if (self.viewStateSeeingBlocks) {
            DWEnvironment *environment = [DWEnvironment sharedInstance];
            DSChain *chain = environment.currentChain;
            self.descriptionLabel.text = [NSString stringWithFormat:NSLocalizedString(@"block #%d of %d", nil),
                                                                    chain.lastBlockHeight,
                                                                    chain.estimatedBlockHeight];
        }
        else {
            self.descriptionLabel.text = NSLocalizedString(@"with Dash blockchain", nil);
        }
    }
}

#pragma mark - Actions

- (void)changeSeeBlocksStateAction:(id)sender {
    self.viewStateSeeingBlocks = !self.viewStateSeeingBlocks;
    [self updateUIForViewStateSeeingBlocks];
}

- (IBAction)retryButtonAction:(id)sender {
    [self.delegate syncViewRetryButtonAction:self];
}

@end

NS_ASSUME_NONNULL_END

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

#import "DWSyncingAlertContentView.h"

#import "DWActionButton.h"
#import "DWEnvironment.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSyncingAlertContentView ()

@property (readonly, nonatomic, strong) UIImageView *syncingImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *subtitleLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWSyncingAlertContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UIImageView *syncingImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon_syncing_large"]];
        syncingImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:syncingImageView];
        _syncingImageView = syncingImageView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.numberOfLines = 0;
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        subtitleLabel.textColor = [UIColor dw_secondaryTextColor];
        subtitleLabel.adjustsFontForContentSizeCategory = YES;
        subtitleLabel.textAlignment = NSTextAlignmentCenter;
        subtitleLabel.numberOfLines = 0;
        [self addSubview:subtitleLabel];
        _subtitleLabel = subtitleLabel;

        DWActionButton *okButton = [[DWActionButton alloc] init];
        okButton.translatesAutoresizingMaskIntoConstraints = NO;
        okButton.small = YES;
        [okButton setTitle:NSLocalizedString(@"OK", nil) forState:UIControlStateNormal];
        [okButton addTarget:self action:@selector(okButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:okButton];

        [syncingImageView setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                          forAxis:UILayoutConstraintAxisVertical];
        [syncingImageView setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                          forAxis:UILayoutConstraintAxisHorizontal];

        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 1
                                                    forAxis:UILayoutConstraintAxisVertical];
        [subtitleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 2
                                                       forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [syncingImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [syncingImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:syncingImageView.bottomAnchor
                                                 constant:16.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

            [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                    constant:8.0],
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:subtitleLabel.trailingAnchor],

            [okButton.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor
                                               constant:38.0],
            [okButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.bottomAnchor constraintEqualToAnchor:okButton.bottomAnchor],
            [okButton.heightAnchor constraintEqualToConstant:32.0],
            [okButton.widthAnchor constraintEqualToConstant:110.0],
        ]];

        // KVO

        [self mvvm_observe:DW_KEYPATH(self, model.syncModel.state)
                      with:^(typeof(self) self, NSNumber *value) {
                          [self updateWithState:self.model.syncModel.state];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.syncModel.progress)
                      with:^(typeof(self) self, NSNumber *value) {
                          const float progress = self.model.syncModel.progress;
                          self.titleLabel.text = [NSString stringWithFormat:@"%@ %0.1f%%", NSLocalizedString(@"Syncing", nil),
                                                                            progress * 100.0];
                          if (self.model.syncModel.state == DWSyncModelState_Syncing) {
                              [self updateWithState:self.model.syncModel.state];
                          }
                      }];
    }
    return self;
}

- (void)okButtonAction:(UIButton *)sender {
    [self.delegate syncingAlertContentView:self okButtonAction:sender];
}

- (void)updateWithState:(DWSyncModelState)syncState {
    switch (syncState) {
        case DWSyncModelState_Syncing:
        case DWSyncModelState_SyncDone: {
            DWEnvironment *environment = [DWEnvironment sharedInstance];
            DSChain *chain = environment.currentChain;
            DSChainManager *chainManager = environment.currentChainManager;
            if (chainManager.syncPhase == DSChainSyncPhase_InitialTerminalBlocks) {
                if (chain.lastTerminalBlockHeight >= chain.estimatedBlockHeight && chainManager.masternodeManager.masternodeListRetrievalQueueCount) {
                    self.subtitleLabel.text = [NSString stringWithFormat:NSLocalizedString(@"masternode list #%d of %d", nil),
                                                                         (int)(chainManager.masternodeManager.masternodeListRetrievalQueueMaxAmount - chainManager.masternodeManager.masternodeListRetrievalQueueCount),
                                                                         (int)chainManager.masternodeManager.masternodeListRetrievalQueueMaxAmount];
                }
                else {
                    self.subtitleLabel.text = [NSString stringWithFormat:NSLocalizedString(@"header #%d of %d", nil),
                                                                         chain.lastTerminalBlockHeight,
                                                                         chain.estimatedBlockHeight];
                }
            }
            else {
                self.subtitleLabel.text = [NSString stringWithFormat:NSLocalizedString(@"block #%d of %d", nil),
                                                                     chain.lastSyncBlockHeight,
                                                                     chain.estimatedBlockHeight];
            }

            break;
        }
        case DWSyncModelState_SyncFailed:
            self.subtitleLabel.text = NSLocalizedString(@"Sync Failed", nil);

            break;
        case DWSyncModelState_NoConnection:
            self.subtitleLabel.text = NSLocalizedString(@"Unable to connect", nil);

            break;
    }

    if (syncState == DWSyncModelState_Syncing) {
        [self showAnimation];
    }
    else {
        [self hideAnimation];
    }
}

- (void)showAnimation {
    if ([self.syncingImageView.layer animationForKey:@"dw_rotationAnimation"]) {
        return;
    }

    CABasicAnimation *rotationAnimation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotationAnimation.fromValue = @0;
    rotationAnimation.toValue = @(M_PI * 2.0);
    rotationAnimation.duration = 1.75;
    rotationAnimation.repeatCount = HUGE_VALF;
    [self.syncingImageView.layer addAnimation:rotationAnimation forKey:@"dw_rotationAnimation"];
}

- (void)hideAnimation {
    [self.syncingImageView.layer removeAllAnimations];
}

@end

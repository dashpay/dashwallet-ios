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

#import "DWUsernamePendingViewController.h"

#import "DWActionButton.h"
#import "DWBaseActionButtonViewController.h"
#import "DWDashPayAnimationView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUsernamePendingViewController ()

@property (null_resettable, strong, nonatomic) UIView *contentView;
@property (null_resettable, strong, nonatomic) DWDashPayAnimationView *progressView;
@property (null_resettable, strong, nonatomic) UILabel *detailLabel;
@property (null_resettable, strong, nonatomic) UIButton *actionButton;

@end

NS_ASSUME_NONNULL_END

@implementation DWUsernamePendingViewController

- (NSAttributedString *)attributedTitle {
    NSDictionary *regularAttributes = @{
        NSFontAttributeName : [UIFont dw_regularFontOfSize:22.0],
        NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
    };

    NSAttributedString *pleaseString =
        [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Please wait", nil)
                                        attributes:regularAttributes];
    return pleaseString;
}

- (void)setUsername:(NSString *)username {
    _username = username;
    [self updateDetailLabel];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_dashBlueColor];

    UIView *centeredView = [[UIView alloc] init];
    centeredView.translatesAutoresizingMaskIntoConstraints = NO;
    [centeredView addSubview:self.progressView];
    [centeredView addSubview:self.detailLabel];

    [self.contentView addSubview:centeredView];
    [self.view addSubview:self.contentView];
    [self.view addSubview:self.actionButton];

    UILayoutGuide *marginsGuide = self.view.layoutMarginsGuide;
    UILayoutGuide *safeAreaGuide = self.view.safeAreaLayoutGuide;

    [self.progressView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self.detailLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [centeredView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

    const CGFloat bottomPadding = [DWBaseActionButtonViewController deviceSpecificBottomPadding];
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor constraintEqualToAnchor:safeAreaGuide.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:marginsGuide.trailingAnchor],

        [self.progressView.topAnchor constraintEqualToAnchor:centeredView.topAnchor],
        [self.progressView.centerXAnchor constraintEqualToAnchor:centeredView.centerXAnchor],

        [self.detailLabel.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor
                                                   constant:10.0],
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:centeredView.leadingAnchor],
        [self.detailLabel.trailingAnchor constraintEqualToAnchor:centeredView.trailingAnchor],
        [self.detailLabel.bottomAnchor constraintEqualToAnchor:centeredView.bottomAnchor],

        [centeredView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [centeredView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [centeredView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [self.actionButton.topAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.actionButton.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [self.actionButton.trailingAnchor constraintEqualToAnchor:marginsGuide.trailingAnchor],
        [safeAreaGuide.bottomAnchor constraintEqualToAnchor:self.actionButton.bottomAnchor
                                                   constant:bottomPadding],
        [self.actionButton.heightAnchor constraintEqualToConstant:DWBottomButtonHeight()],
    ]];

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(contentSizeCategoryDidChangeNotification)
                               name:UIContentSizeCategoryDidChangeNotification
                             object:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.progressView startAnimating];
}

#pragma mark - Private

- (UIView *)contentView {
    if (_contentView == nil) {
        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = [UIColor dw_dashBlueColor];
        _contentView = contentView;
    }
    return _contentView;
}

- (DWDashPayAnimationView *)progressView {
    if (_progressView == nil) {
        DWDashPayAnimationView *progressView = [[DWDashPayAnimationView alloc] initWithFrame:CGRectZero];
        progressView.translatesAutoresizingMaskIntoConstraints = NO;
        _progressView = progressView;
    }
    return _progressView;
}

- (UILabel *)detailLabel {
    if (_detailLabel == nil) {
        UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        detailLabel.numberOfLines = 0;
        detailLabel.adjustsFontSizeToFitWidth = YES;
        detailLabel.minimumScaleFactor = 0.5;
        detailLabel.textAlignment = NSTextAlignmentCenter;
        _detailLabel = detailLabel;
    }
    return _detailLabel;
}

- (UIButton *)actionButton {
    if (_actionButton == nil) {
        DWActionButton *actionButton = [[DWActionButton alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, 54.0)];
        actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        actionButton.layer.cornerRadius = 8;
        actionButton.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        [actionButton setBackgroundColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [actionButton setTitleColor:[UIColor dw_dashBlueColor] forState:UIControlStateNormal];
        [actionButton setTitleColor:[[UIColor dw_dashBlueColor] colorWithAlphaComponent:0.5] forState:UIControlStateHighlighted];
        [actionButton setTitle:NSLocalizedString(@"Let me know when it’s done", nil)
                      forState:UIControlStateNormal];
        [actionButton addTarget:self
                         action:@selector(actionButtonAction:)
               forControlEvents:UIControlEventTouchUpInside];
        _actionButton = actionButton;
    }
    return _actionButton;
}

- (void)actionButtonAction:(id)sender {
    [self.delegate usernamePendingViewControllerAction:self];
}

- (void)contentSizeCategoryDidChangeNotification {
    [self updateDetailLabel];
}

- (void)updateDetailLabel {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    [result beginEditing];

    NSString *formattedString = [NSString
        stringWithFormat:NSLocalizedString(@"Your username %@ is being created on the Dash Network", nil),
                         self.username];
    NSAttributedString *detail = [[NSAttributedString alloc]
        initWithString:formattedString
            attributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleBody], NSForegroundColorAttributeName : [UIColor dw_lightTitleColor]}];
    [result appendAttributedString:detail];

    NSRange usernameRange = [formattedString rangeOfString:self.username];
    [result setAttributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline], NSForegroundColorAttributeName : [UIColor dw_lightTitleColor]} range:usernameRange];

    [result endEditing];

    self.detailLabel.attributedText = result;
}

@end

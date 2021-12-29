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

#import "DWTodayViewController.h"

#import <NotificationCenter/NotificationCenter.h>

#import "BRBubbleView.h"
#import "DWAppGroupOptions.h"
#import "UIImage+Utils.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const SCAN_URL = @"dashwallet://x-callback-url/scanqr";
static NSString *const OPEN_URL = @"dashwallet://";

static CGSize const QR_SIZE = {240.0, 240.0};
static CGSize const HOLE_SIZE = {58.0, 58.0};
static CGSize const LOGO_SIZE = {54.0, 54.0};

@interface DWTodayViewController () <NCWidgetProviding>

@property (nonatomic, strong) IBOutlet UIView *qrButtonVibrancyContentView;
@property (nonatomic, strong) IBOutlet UIImageView *qrImage;
@property (nonatomic, strong) IBOutlet UILabel *addressLabel;
@property (nonatomic, strong) IBOutlet UILabel *sendLabel;
@property (nonatomic, strong) IBOutlet UILabel *receiveLabel;
@property (nonatomic, strong) IBOutlet UIButton *setupWalletButton;
@property (nonatomic, strong) IBOutlet UILabel *scanLabel;
@property (nonatomic, strong) IBOutlet UIView *noDataViewContainer;
@property (nonatomic, strong) IBOutlet UIView *topViewContainer;

@property (nonatomic, strong) NSData *qrCodeData;
@property (nullable, nonatomic, strong) BRBubbleView *bubbleView;

@end

@implementation DWTodayViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    UIVisualEffect *effect = nil;
    if (@available(iOS 13.0, *)) {
        effect = [UIVibrancyEffect widgetEffectForVibrancyStyle:UIVibrancyEffectStyleLabel];
    }
    else {
        effect = [UIVibrancyEffect widgetPrimaryVibrancyEffect];
    }

    UIVisualEffectView *visualEffectView = [[UIVisualEffectView alloc] initWithEffect:effect];
    visualEffectView.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *qrScanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    qrScanButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *qrImage = [UIImage imageNamed:@"icon_scan"];
    [qrScanButton setImage:qrImage forState:UIControlStateNormal];
    [qrScanButton addTarget:self
                     action:@selector(scanButtonAction:)
           forControlEvents:UIControlEventTouchUpInside];
    [visualEffectView.contentView addSubview:qrScanButton];

    UIView *qrButtonContentView = self.qrButtonVibrancyContentView;
    [qrButtonContentView addSubview:visualEffectView];

    [NSLayoutConstraint activateConstraints:@[
        [visualEffectView.topAnchor constraintEqualToAnchor:qrButtonContentView.topAnchor],
        [visualEffectView.leadingAnchor constraintEqualToAnchor:qrButtonContentView.leadingAnchor],
        [visualEffectView.bottomAnchor constraintEqualToAnchor:qrButtonContentView.bottomAnchor],
        [visualEffectView.trailingAnchor constraintEqualToAnchor:qrButtonContentView.trailingAnchor],

        [qrScanButton.topAnchor constraintEqualToAnchor:qrButtonContentView.topAnchor],
        [qrScanButton.leadingAnchor constraintEqualToAnchor:qrButtonContentView.leadingAnchor],
        [qrScanButton.bottomAnchor constraintEqualToAnchor:qrButtonContentView.bottomAnchor],
        [qrScanButton.trailingAnchor constraintEqualToAnchor:qrButtonContentView.trailingAnchor],
    ]];

    self.extensionContext.widgetLargestAvailableDisplayMode = NCWidgetDisplayModeExpanded;

    UIColor *textColor = nil;
    if (@available(iOS 13.0, *)) {
        textColor = [UIColor secondaryLabelColor];
    }
    else {
        textColor = [UIColor darkGrayColor];
    }
    self.addressLabel.textColor = textColor;
    self.sendLabel.textColor = textColor;
    self.receiveLabel.textColor = textColor;
    self.scanLabel.textColor = textColor;

    self.sendLabel.text = NSLocalizedString(@"Send", nil);
    self.receiveLabel.text = NSLocalizedString(@"Receive", nil);
    self.scanLabel.text = NSLocalizedString(@"Scan QR Code", nil);
    [self.setupWalletButton setTitle:NSLocalizedString(@"Setup Wallet", nil) forState:UIControlStateNormal];

    [self updateReceiveMoneyUI];
}

#pragma mark - NCWidgetProviding

- (void)widgetActiveDisplayModeDidChange:(NCWidgetDisplayMode)activeDisplayMode withMaximumSize:(CGSize)maxSize {
    if (activeDisplayMode == NCWidgetDisplayModeExpanded) {
        self.preferredContentSize = CGSizeMake(maxSize.width, maxSize.width * 3 / 4);
    }
    else {
        self.preferredContentSize = maxSize;
    }
}

- (void)widgetPerformUpdateWithCompletionHandler:(void (^)(NCUpdateResult))completionHandler {
    [self.bubbleView popOut];
    self.bubbleView = nil;
    if (!completionHandler) {
        return;
    }

    // Perform any setup necessary in order to update the view.
    NSData *data = [DWAppGroupOptions sharedInstance].receiveRequestData;

    // If an error is encountered, use NCUpdateResultFailed
    // If there's no update required, use NCUpdateResultNoData
    // If there's an update, use NCUpdateResultNewData
    if ([self.qrCodeData isEqualToData:data]) {
        self.noDataViewContainer.hidden = YES;
        self.topViewContainer.hidden = NO;
        completionHandler(NCUpdateResultNoData);
    }
    else if (self.qrCodeData) {
        self.qrCodeData = data;
        self.noDataViewContainer.hidden = YES;
        self.topViewContainer.hidden = NO;
        [self updateReceiveMoneyUI];
        completionHandler(NCUpdateResultNewData);
    }
    else {
        self.noDataViewContainer.hidden = NO;
        self.topViewContainer.hidden = YES;
        completionHandler(NCUpdateResultFailed);
    }
}

#pragma mark - Actions

- (void)scanButtonAction:(UIButton *)sender {
    [self.extensionContext openURL:[NSURL URLWithString:SCAN_URL] completionHandler:nil];
}

- (IBAction)openAppButtonTapped:(id)sender {
    [self.extensionContext openURL:[NSURL URLWithString:OPEN_URL] completionHandler:nil];
}

- (IBAction)qrImageTapped:(id)sender {
    // UIMenuControl doesn't seem to work in an NCWidget, so use a BRBubbleView that looks nearly the same
    if (self.bubbleView) {
        if (CGRectContainsPoint(self.bubbleView.frame,
                                [(UITapGestureRecognizer *)sender locationInView:self.bubbleView.superview])) {
            [UIPasteboard generalPasteboard].string = self.addressLabel.text;
        }

        [self.bubbleView popOut];
        self.bubbleView = nil;
    }
    else {
        self.bubbleView = [BRBubbleView viewWithText:NSLocalizedString(@"Copy", nil)
                                            tipPoint:CGPointMake(self.addressLabel.center.x, self.addressLabel.frame.origin.y - 5.0)
                                        tipDirection:BRBubbleTipDirectionDown];
        self.bubbleView.alpha = 0;
        UIFont *font = [UIFont systemFontOfSize:14.0];
        NSParameterAssert(font);
        self.bubbleView.font = font;
        self.bubbleView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        [self.addressLabel.superview addSubview:self.bubbleView];
        [self.bubbleView becomeFirstResponder]; // this will cause bubbleview to hide when it loses firstresponder status
        [UIView animateWithDuration:0.2
                         animations:^{
                             self.bubbleView.alpha = 1.0;
                         }];
    }
}

- (IBAction)widgetTapped:(id)sender {
    [self.bubbleView popOut];
    self.bubbleView = nil;
}

#pragma mark - Private

- (void)updateReceiveMoneyUI {
    self.qrCodeData = [DWAppGroupOptions sharedInstance].receiveRequestData;

    if (self.qrCodeData && self.qrImage.bounds.size.width > 0) {
        NSData *imageData = [DWAppGroupOptions sharedInstance].receiveQRImageData;
        UIImage *image = [UIImage imageWithData:imageData];
        UIImage *resizedImage = [image dw_resize:QR_SIZE withInterpolationQuality:kCGInterpolationNone];
        UIImage *overlayLogo = [[UIImage imageNamed:@"dash_logo_qr"] dw_resize:LOGO_SIZE
                                                      withInterpolationQuality:kCGInterpolationMedium];
        resizedImage = [resizedImage dw_imageByCuttingHoleInCenterWithSize:HOLE_SIZE];
        UIImage *result = [resizedImage dw_imageByMergingWithImage:overlayLogo];

        self.qrImage.image = result;
    }

    self.addressLabel.text = [DWAppGroupOptions sharedInstance].receiveAddress;
}

@end

NS_ASSUME_NONNULL_END

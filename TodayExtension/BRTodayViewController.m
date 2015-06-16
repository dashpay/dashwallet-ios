//
//  TodayViewController.m
//  TodayWidget
//
//  Created by Henry on 6/14/15.
//  Copyright (c) 2015 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "BRTodayViewController.h"
#import <NotificationCenter/NotificationCenter.h>
#import "UIImage+QRCode.h"
#import "UIImage+NegativeImage.h"
#import "BRAppGroupConstants.h"
#import "NSUserDefaults+AppGroup.h"

static NSString *const kBRScanQRCodeURLScheme = @"bread://x-callback-url/scanqr";

@interface BRTodayViewController () <NCWidgetProviding>
@property (nonatomic, weak) IBOutlet UIView *imageViewContainer;
@property (nonatomic, weak) IBOutlet UILabel *hashLabel;
@property (nonatomic, weak) IBOutlet UIView *scanQRButtonContainerView;
@property (weak, nonatomic) IBOutlet UIButton *scanButton;
@property (nonatomic, strong) NSData *qrCodeData;
@property (nonatomic, strong) UIImageView *qrCodeImageView;
@property (nonatomic, strong) UIVisualEffectView *qrCodeVisualEffectView;
@property (nonatomic, strong) UIVisualEffectView *scanQrCodeButtonVisualEffectView;
@end

@implementation BRTodayViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.imageViewContainer addSubview:self.qrCodeVisualEffectView];
	[self.scanQRButtonContainerView insertSubview:self.scanQrCodeButtonVisualEffectView belowSubview:self.scanButton];
	[self updateReceiveMoneyUI];
}

- (void)widgetPerformUpdateWithCompletionHandler:(void (^)(NCUpdateResult))completionHandler {
	// Perform any setup necessary in order to update the view.
	NSData *data = [[NSUserDefaults appGroupUserDefault] objectForKey:kBRSharedContainerDataWalletRequestDataKey];
	// If an error is encountered, use NCUpdateResultFailed
	// If there's no update required, use NCUpdateResultNoData
	// If there's an update, use NCUpdateResultNewData
	if ([self.qrCodeData isEqualToData:data]) {
		completionHandler(NCUpdateResultNoData);
	} else if (self.qrCodeData) {
		self.qrCodeData = data;
		completionHandler(NCUpdateResultNewData);
	} else {
		completionHandler(NCUpdateResultFailed);
	}
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self updateReceiveMoneyUI];
}

- (void)updateReceiveMoneyUI {
	self.qrCodeData = [[NSUserDefaults appGroupUserDefault] objectForKey:kBRSharedContainerDataWalletRequestDataKey];
	NSString *receiveAddress = [[NSUserDefaults appGroupUserDefault] objectForKey:kBRSharedContainerDataWalletReceiveAddressKey];
	if (!CGSizeEqualToSize(self.imageViewContainer.frame.size,CGSizeZero) && self.qrCodeData) {
		[self.qrCodeImageView removeFromSuperview];
		UIImage *image = [UIImage imageWithQRCodeData:self.qrCodeData size:CGSizeMake(self.imageViewContainer.frame.size.width, self.imageViewContainer.frame.size.height)];
		image = [image negativeImage];
		self.qrCodeImageView = [[UIImageView alloc] initWithImage:image];
        // if accessbility reduced Transparency is on, we use original image so it's easier to scan
        if (UIAccessibilityIsReduceTransparencyEnabled()) {
            [self.qrCodeVisualEffectView addSubview:self.qrCodeImageView];
        } else {
            [self.qrCodeVisualEffectView.contentView addSubview:self.qrCodeImageView];
        }
	}
	self.hashLabel.text = receiveAddress;
}

- (UIVisualEffectView*) qrCodeVisualEffectView {
	if (!_qrCodeVisualEffectView) {
		_qrCodeVisualEffectView = [[UIVisualEffectView alloc] initWithEffect:[UIVibrancyEffect notificationCenterVibrancyEffect]];
		_qrCodeVisualEffectView.frame = self.imageViewContainer.bounds;
		_qrCodeVisualEffectView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
	}
	return _qrCodeVisualEffectView;
}

- (UIVisualEffectView*) scanQrCodeButtonVisualEffectView {
	if (!_scanQrCodeButtonVisualEffectView) {
		_scanQrCodeButtonVisualEffectView = [[UIVisualEffectView alloc] initWithEffect:[UIVibrancyEffect notificationCenterVibrancyEffect]];
		_scanQrCodeButtonVisualEffectView.frame = self.scanQRButtonContainerView.bounds;
		_scanQrCodeButtonVisualEffectView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
		UIImageView *scanQRCodeButtonImageView =  [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanbutton"]];
		scanQRCodeButtonImageView.frame = self.scanQRButtonContainerView.bounds;
		scanQRCodeButtonImageView.contentMode = UIViewContentModeScaleAspectFit;
		scanQRCodeButtonImageView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        if (UIAccessibilityIsReduceTransparencyEnabled()) {
            [_scanQrCodeButtonVisualEffectView addSubview:scanQRCodeButtonImageView];
        } else {
            [_scanQrCodeButtonVisualEffectView.contentView addSubview:scanQRCodeButtonImageView];
        }
	}
	return _scanQrCodeButtonVisualEffectView;
}

#pragma mark - NCWidgetProviding

- (UIEdgeInsets)widgetMarginInsetsForProposedMarginInsets:(UIEdgeInsets)defaultMarginInsets {
	return UIEdgeInsetsZero;
}

#pragma mark - UI Events

- (IBAction)scanButtonTapped:(UIButton *)sender {
	[self.extensionContext openURL:[NSURL URLWithString:kBRScanQRCodeURLScheme] completionHandler:nil];
}


@end

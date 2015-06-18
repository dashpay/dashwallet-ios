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
#import "BRTodayWidgetButton.h"
#import "BRVisualEffectButton.h"

static NSString *const kBRScanQRCodeURLScheme = @"bread://x-callback-url/scanqr";
static NSString *const kBROpenBreadwalletScheme = @"bread://";


@interface BRTodayViewController () <NCWidgetProviding>
@property (nonatomic, weak) IBOutlet UIView *imageViewContainer;
@property (nonatomic, weak) IBOutlet UILabel *hashLabel;
@property (nonatomic, weak) IBOutlet UIView *scanQRButtonContainerView;
@property (nonatomic, weak) IBOutlet UIView *noDataViewContainer;
@property (nonatomic, weak) IBOutlet UIView *topViewContainer;
@property (nonatomic, weak) IBOutlet UIView *openAppButtonContainer;
@property (nonatomic, strong) NSData *qrCodeData;
@property (nonatomic, strong) UIImageView *qrCodeImageView;
@property (nonatomic, strong) UIVisualEffectView *qrCodeVisualEffectView;
@property (nonatomic, strong) UIVisualEffectView *scanQrCodeButtonVisualEffectView;
@property (nonatomic, strong) UIVisualEffectView *openAppVisualEffectView;
@property (nonatomic, strong) UIButton *openAppButton;
@property (nonatomic, strong) UIButton *scanButton;
@end

@implementation BRTodayViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.imageViewContainer addSubview:self.qrCodeVisualEffectView];
	[self.scanQRButtonContainerView addSubview:self.scanButton];
    [self.openAppButtonContainer addSubview:self.openAppButton];
	[self updateReceiveMoneyUI];
}

- (void)widgetPerformUpdateWithCompletionHandler:(void (^)(NCUpdateResult))completionHandler {
	// Perform any setup necessary in order to update the view.
	NSData *data = [[NSUserDefaults appGroupUserDefault] objectForKey:kBRSharedContainerDataWalletRequestDataKey];
	// If an error is encountered, use NCUpdateResultFailed
	// If there's no update required, use NCUpdateResultNoData
	// If there's an update, use NCUpdateResultNewData
	if ([self.qrCodeData isEqualToData:data]) {
        self.noDataViewContainer.hidden = YES;
        self.topViewContainer.hidden = NO;
		completionHandler(NCUpdateResultNoData);
	} else if (self.qrCodeData) {
		self.qrCodeData = data;
        self.noDataViewContainer.hidden = YES;
        self.topViewContainer.hidden = NO;
        [self updateReceiveMoneyUI];
		completionHandler(NCUpdateResultNewData);
	} else {
        self.noDataViewContainer.hidden = NO;
        self.topViewContainer.hidden = YES;
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

- (UIVisualEffectView*) openAppVisualEffectView {
    if (!_openAppVisualEffectView) {
        _openAppVisualEffectView = [[UIVisualEffectView alloc] initWithEffect:[UIVibrancyEffect notificationCenterVibrancyEffect]];
        _openAppVisualEffectView.frame = self.openAppButtonContainer.bounds;
        _openAppVisualEffectView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [_openAppVisualEffectView.contentView addSubview:self.openAppButton];
    }
    return _openAppVisualEffectView;
}

- (UIButton*)openAppButton {
    if (!_openAppButton) {
        _openAppButton = [[BRVisualEffectButton alloc] initWithFrame:self.openAppButtonContainer.bounds];
        _openAppButton.userInteractionEnabled = YES;
        _openAppButton.titleLabel.font = [UIFont systemFontOfSize:12];
        [_openAppButton setTitle:@"Open App" forState:UIControlStateNormal];
        [_openAppButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [_openAppButton addTarget:self action:@selector(openAppButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _openAppButton;
}

- (UIButton*)scanButton {
    if (!_scanButton) {
        _scanButton = [[BRVisualEffectButton alloc] initWithFrame:self.scanQRButtonContainerView.bounds];
        _scanButton.userInteractionEnabled = YES;
        [_scanButton setImage:[UIImage imageNamed:@"scanbutton"] forState:UIControlStateNormal];
        [_scanButton addTarget:self action:@selector(scanButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _scanButton;
}

#pragma mark - NCWidgetProviding

- (UIEdgeInsets)widgetMarginInsetsForProposedMarginInsets:(UIEdgeInsets)defaultMarginInsets {
	return UIEdgeInsetsZero;
}

#pragma mark - UI Events

- (IBAction)scanButtonTapped:(UIButton *)sender {
	[self.extensionContext openURL:[NSURL URLWithString:kBRScanQRCodeURLScheme] completionHandler:nil];
}

- (IBAction)openAppButtonTapped:(id)sender {
    [self.extensionContext openURL:[NSURL URLWithString:kBROpenBreadwalletScheme] completionHandler:nil];
}


@end

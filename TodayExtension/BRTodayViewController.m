//
//  TodayViewController.m
//  TodayWidget
//
//  Created by Henry Tsai on 6/13/15.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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
#import "NSUserDefaults+AppGroup.h"
#import "UIImage+QRCode.h"
#import "BRAppGroupConstants.h"

static NSString *const kBRScanQRCodeURLScheme = @"bread://x-callback-url/scanqr";
static CGFloat const kBRTodayWidgetButtonCornerRadius = 4;

@interface BRTodayViewController () <NCWidgetProviding>
@property (nonatomic, weak) IBOutlet UIButton *sendMoneyButton;
@property (nonatomic, weak) IBOutlet UIButton *receiveMoneyButton;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *qrCodeImageViewWidthContraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *qrCodeImageViewHeightContraint;
@property (nonatomic, weak) IBOutlet UIImageView *qrCodeImageView;
@property (nonatomic, strong) NSData *qrCodeData;
@end

@implementation BRTodayViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view from its nib.
	self.qrCodeData = [[NSUserDefaults appGroupUserDefault] objectForKey:kBRSharedContainerDataWalletRequestDataKey];
	self.qrCodeImageView.image = [UIImage imageWithQRCodeData:self.qrCodeData size:CGSizeMake([self maxQRCodeImageWidth], [self maxQRCodeImageWidth])];
	self.sendMoneyButton.layer.cornerRadius = kBRTodayWidgetButtonCornerRadius;
	self.receiveMoneyButton.layer.cornerRadius = kBRTodayWidgetButtonCornerRadius;
	[self updateQrCodeImageViewHiddenStatus];
}

#pragma mark - NCWidgetProviding

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

- (UIEdgeInsets)widgetMarginInsetsForProposedMarginInsets:(UIEdgeInsets)defaultMarginInsets {
	return UIEdgeInsetsZero;
}


#pragma mark - UI event

- (IBAction)sendMoneyButtonTapped:(UIButton *)sender {
	[self.extensionContext openURL:[NSURL URLWithString:kBRScanQRCodeURLScheme] completionHandler:nil];
}

- (IBAction)receiveMoneyButtonTapped:(id)sender {
	if ([self isQRCodeImageShown]) {
		self.qrCodeImageViewWidthContraint.constant = 0;
		self.qrCodeImageViewHeightContraint.constant = 0;
	} else {
		self.qrCodeImageViewWidthContraint.constant = [self maxQRCodeImageWidth];
		self.qrCodeImageViewHeightContraint.constant = [self maxQRCodeImageWidth];
	}
	if ([self isQRCodeImageShown]) {
		self.qrCodeImageView.hidden = ![self isQRCodeImageShown];
	}
	[self.view setNeedsUpdateConstraints];
	[UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
	         [self.view layoutIfNeeded];
	 } completion:^(BOOL finished) {
	         self.qrCodeImageView.hidden = ![self isQRCodeImageShown];
	 }];
}

#pragma mark - helper methods

- (CGFloat)maxQRCodeImageWidth {
	return self.view.frame.size.width * 0.9;
}

- (BOOL)isQRCodeImageShown {
	return (self.qrCodeImageViewWidthContraint.constant > 1);
}

- (void)updateQrCodeImageViewHiddenStatus {
	self.qrCodeImageView.hidden = ![self isQRCodeImageShown];
}


@end

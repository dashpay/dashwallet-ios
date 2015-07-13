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
#import "UIImage+Utility.h"
#import "BRAppGroupConstants.h"
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
@property (nonatomic, strong) UIButton *openAppButton;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *qrCodeView;
@property (nonatomic, strong) NSUserDefaults *appGroupUserDefault;
@end

@implementation BRTodayViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.topViewContainer.alpha = self.noDataViewContainer.alpha = 0.0;
    [self.imageViewContainer addSubview:self.qrCodeView];
    [self.scanQRButtonContainerView addSubview:self.scanButton];
    [self.openAppButtonContainer addSubview:self.openAppButton];
    [self updateReceiveMoneyUI];

    [UIView animateWithDuration:0.2 animations:^{
        self.topViewContainer.alpha = self.noDataViewContainer.alpha = 1.0;
    }];
}

- (void)widgetPerformUpdateWithCompletionHandler:(void (^)(NCUpdateResult))completionHandler {
    if (completionHandler) {
        // Perform any setup necessary in order to update the view.
        NSData *data = [self.appGroupUserDefault objectForKey:kBRSharedContainerDataWalletRequestDataKey];
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
}

- (NSUserDefaults*)appGroupUserDefault {
    if (!_appGroupUserDefault){
        _appGroupUserDefault = [[NSUserDefaults alloc] initWithSuiteName:kBRAppGroupIdentifier];
    }
    return _appGroupUserDefault;
}


- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self updateReceiveMoneyUI];
}

- (void)updateReceiveMoneyUI {
    self.qrCodeData = [self.appGroupUserDefault objectForKey:kBRSharedContainerDataWalletRequestDataKey];
    NSString *receiveAddress = [self.appGroupUserDefault objectForKey:kBRSharedContainerDataWalletReceiveAddressKey];
    if (!CGSizeEqualToSize(self.imageViewContainer.frame.size,CGSizeZero) && self.qrCodeData) {
        [self.qrCodeImageView removeFromSuperview];
        UIImage *image = [UIImage imageWithQRCodeData:self.qrCodeData size:self.imageViewContainer.bounds.size color:[CIColor colorWithRed:1.0 green:1.0 blue:1.0]];
        [self.qrCodeView setImage:image forState:UIControlStateNormal];
    }
    self.hashLabel.text = receiveAddress;
}

- (UIButton*)openAppButton {
    if (!_openAppButton) {
        _openAppButton = [[BRVisualEffectButton alloc] initWithFrame:self.openAppButtonContainer.bounds];
        _openAppButton.userInteractionEnabled = YES;
        _openAppButton.titleLabel.font = [UIFont systemFontOfSize:14];
        [_openAppButton setTitle:@"setup wallet" forState:UIControlStateNormal];
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

- (UIButton*)qrCodeView {
    if (!_qrCodeView) {
        _qrCodeView = [[BRVisualEffectButton alloc] initWithFrame:self.imageViewContainer.bounds];
        _qrCodeView.userInteractionEnabled = NO;
        _qrCodeView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

    }
    return _qrCodeView;
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

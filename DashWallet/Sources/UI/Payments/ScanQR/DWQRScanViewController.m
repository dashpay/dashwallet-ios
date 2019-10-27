//
//  DWQRScanViewController.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 21/12/2017.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
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

#import "DSEventManager.h"
#import "DWQRScanModel.h"
#import "DWQRScanView.h"

#import "DWQRScanViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWQRScanViewController ()

@property (strong, nonatomic) DWQRScanView *view;

@end

@implementation DWQRScanViewController

@dynamic view;

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = [[DWQRScanModel alloc] init];
    }
    return self;
}

- (void)loadView {
    self.view = [[DWQRScanView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.model = self.model;

    if (!self.model.isCameraDeniedOrRestricted) {
        __weak typeof(self) weakSelf = self;
        [self.model startPreviewCompletion:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf.view connectCaptureSession];
        }];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (self.model.isCameraDeniedOrRestricted) {
        NSString *displayName = [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"];
        NSString *titleString =
            [NSString stringWithFormat:NSLocalizedString(@"%@ is not allowed to access the camera", nil),
                                       displayName];
        NSString *messageString =
            [NSString stringWithFormat:
                          NSLocalizedString(@"Allow camera access in\nSettings->Privacy->Camera->%@", nil),
                          displayName];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:titleString
                                                                       message:messageString
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"OK", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:okAction];

        UIAlertAction *settingsAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Settings", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_Nonnull action) {
                        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
                            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                        }
                    }];
        [alert addAction:settingsAction];

        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    [self.view disconnectCaptureSession];
    [self.model stopPreview];
}

@end

NS_ASSUME_NONNULL_END

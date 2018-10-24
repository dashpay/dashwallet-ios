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

#import "DWQRScanView.h"
#import "DWQRScanViewModel.h"
#import "BREventManager.h"

#import "DWQRScanViewController.h"

@interface DWQRScanViewController ()

@property (strong, nonatomic) DWQRScanView *view;

@end

@implementation DWQRScanViewController

@dynamic view;

- (instancetype)init {
    self = [super init];
    if (self) {
        _viewModel = [[DWQRScanViewModel alloc] init];
    }
    return self;
}

- (void)loadView {
    self.view = [[DWQRScanView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.viewModel = self.viewModel;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if (self.viewModel.isCameraDeniedOrRestricted) {
        [BREventManager saveEvent:@"scan:camera_denied"];
        NSString *displayName = [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"];
        NSString *titleString = [NSString stringWithFormat:NSLocalizedString(@"%@ is not allowed to access the camera", nil),
                                 displayName];
        NSString *messageString = [NSString stringWithFormat:NSLocalizedString(@"\nallow camera access in\n"
                                                                               "Settings->Privacy->Camera->%@", nil),
                                   displayName];
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:titleString
                                                                                 message:messageString
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"ok", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
        [alertController addAction:okAction];
        
        UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }
        }];
        [alertController addAction:settingsAction];
        
        [self presentViewController:alertController animated:YES completion:nil];
    }
    else {
        [self.viewModel startPreview];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self.viewModel stopPreview];
}

@end

//
//  DWMigrationViewController.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 10/11/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWMigrationViewController.h"

#import "DWMigrationViewModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMigrationViewController ()

@end

@implementation DWMigrationViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MigrationStoryboard" bundle:nil];
    DWMigrationViewController *controller = [storyboard instantiateInitialViewController];
    return controller;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSParameterAssert(self.viewModel);

    [self mvvm_observe:@"viewModel.state" with:^(__typeof__(self) self, NSNumber * value) {
        if (self.viewModel.state == DWMigrationViewModelStateDone) {
            [self.delegate migrationViewController:self didFinishWithDeferredLaunchOptions:self.viewModel.deferredLaunchOptions];
        }
    }];

    [self.viewModel startMigration];
}

@end

NS_ASSUME_NONNULL_END

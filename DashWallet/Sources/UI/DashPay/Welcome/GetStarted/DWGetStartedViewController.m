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

#import "DWGetStartedViewController.h"

#import "DWGetStartedContentViewController.h"
#import "DWUIKit.h"

@interface DWGetStartedViewController ()

@end

@implementation DWGetStartedViewController

+ (BOOL)isActionButtonInNavigationBar {
    return NO;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Continue", nil);
}

- (BOOL)requiresNoNavigationBar {
    return YES;
}

- (instancetype)initWithPage:(DWGetStartedPage)page {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _page = page;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.actionButton.enabled = YES;
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self setupContentView:contentView];

    DWGetStartedContentViewController *content = [[DWGetStartedContentViewController alloc] initWithPage:self.page];
    [self dw_embedChild:content inContainer:contentView];
}

- (void)actionButtonAction:(id)sender {
    [self.delegate getStartedViewControllerDidContinue:self];
}


@end

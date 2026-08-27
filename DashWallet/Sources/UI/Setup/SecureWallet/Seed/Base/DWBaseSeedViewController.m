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

#import "DWBaseSeedViewController.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};

@interface DWBaseSeedViewController ()

@property (nullable, nonatomic, strong) UIScrollView *scrollView;

@end

@implementation DWBaseSeedViewController

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Continue", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self baseSeedView_setup];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.scrollView flashScrollIndicators];
}

#pragma mark - Private

- (void)baseSeedView_setup {
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.backgroundColor = self.view.backgroundColor;
    scrollView.scrollIndicatorInsets = SCROLL_INDICATOR_INSETS;
    self.scrollView = scrollView;

    [self setupContentView:scrollView];
}

@end

NS_ASSUME_NONNULL_END

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

#import "DWSeedPhraseViewController.h"

#import "DWSeedPhraseControllerModel.h"
#import "DWSeedPhraseTitledView.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const COMPACT_PADDING = 16.0;

@interface DWSeedPhraseViewController ()

@property (nonatomic, strong) DWSeedPhraseControllerModel *model;

@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property (strong, nonatomic) IBOutlet UIButton *continueButton;

@property (nonatomic, strong) DWSeedPhraseTitledView *seedPhraseView;
@property (nonatomic, strong) NSLayoutConstraint *seedPhraseViewTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *seedPhraseViewBottomConstraint;

@end

@implementation DWSeedPhraseViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"SeedPhrase" bundle:nil];
    DWSeedPhraseViewController *controller = [storyboard instantiateInitialViewController];
    NSString *title = NSLocalizedString(@"Please write this down", nil);
    controller.model = [[DWSeedPhraseControllerModel alloc] initWithSubTitle:title];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

#pragma mark - Private

- (void)setupView {
    self.title = NSLocalizedString(@"Backup Wallet", nil);

    [self.continueButton setTitle:NSLocalizedString(@"Continue", nil)
                         forState:UIControlStateNormal];

    DWSeedPhraseTitledView *seedPhraseView = [[DWSeedPhraseTitledView alloc] initWithType:DWSeedPhraseType_Preview];
    seedPhraseView.translatesAutoresizingMaskIntoConstraints = NO;
    seedPhraseView.model = self.model;
    [self.scrollView addSubview:seedPhraseView];

    self.seedPhraseViewTopConstraint = [seedPhraseView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor
                                                                                constant:COMPACT_PADDING];
    self.seedPhraseViewBottomConstraint = [seedPhraseView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor];

    [NSLayoutConstraint activateConstraints:@[
        self.seedPhraseViewTopConstraint,
        [seedPhraseView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        self.seedPhraseViewBottomConstraint,
        [seedPhraseView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [seedPhraseView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];
}

@end

NS_ASSUME_NONNULL_END

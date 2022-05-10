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

#import "DWToolsExportCSVAlert.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWToolsExportCSVAlert ()

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;

@end

@implementation DWToolsExportCSVAlert

@synthesize providedActions = _providedActions;

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"ExportCSVStoryboard" bundle:nil];
    DWToolsExportCSVAlert *controller = [storyboard instantiateInitialViewController];

    return controller;
}

- (NSArray<DWAlertAction *> *)providedActions {
    if (!_providedActions) {
        __weak typeof(self) weakSelf = self;
        DWAlertAction *cancelAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                               style:DWAlertActionStyleCancel
                                                             handler:^(DWAlertAction *_Nonnull action) {
                                                                 __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                 if (!strongSelf) {
                                                                     return;
                                                                 }

                                                                 [strongSelf.delegate upholdLogoutTutorialViewControllerDidCancel:strongSelf];
                                                             }];

        _providedActions = @[ cancelAction ];
    }
    return _providedActions;
}

- (DWAlertAction *)preferredAction {
    return self.providedActions.lastObject;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.text = NSLocalizedString(@"Export CSV", nil);
    self.descriptionLabel.text = NSLocalizedString(@"Please wait until the wallet is fully synced before exporting your transaction history", nil);
}

@end

NS_ASSUME_NONNULL_END

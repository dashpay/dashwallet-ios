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

#import "UIViewController+DWShareReceiveInfo.h"

#import "DWReceiveModelProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (DWShareReceiveInfo)

- (void)dw_shareReceiveInfo:(id<DWReceiveModelProtocol>)model sender:(UIButton *)sender {
    NSMutableArray *activityItems = [NSMutableArray array];

    NSString *paymentAddressOrRequest = [model paymentAddressOrRequestToShare];
    if (paymentAddressOrRequest) {
        [activityItems addObject:paymentAddressOrRequest];
    }

    if (model.qrCodeImage) {
        [activityItems addObject:model.qrCodeImage];
    }

    NSAssert(activityItems.count > 0, @"Invalid state");
    if (activityItems.count == 0) {
        return;
    }

    UIActivityViewController *activityViewController =
        [[UIActivityViewController alloc] initWithActivityItems:activityItems
                                          applicationActivities:nil];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityViewController.popoverPresentationController.sourceView = sender;
        activityViewController.popoverPresentationController.sourceRect = sender.bounds;
    }
    [self presentViewController:activityViewController
                       animated:YES
                     completion:nil];
}

@end

NS_ASSUME_NONNULL_END

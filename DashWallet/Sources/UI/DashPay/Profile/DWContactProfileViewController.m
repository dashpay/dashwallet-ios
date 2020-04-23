//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWContactProfileViewController.h"

#import "DWContactItem.h"
#import "DWSendAmountViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactProfileViewController ()

@property (strong, nonatomic) IBOutlet UILabel *usernameLabel;
@property (strong, nonatomic) IBOutlet UIButton *payButton;
@property (strong, nonatomic) IBOutlet UIStackView *incomingContactActionsView;
@property (strong, nonatomic) IBOutlet UILabel *outgoingStatusLabel;

@property (nonatomic, strong) id<DWContactItem> contact;

@end

NS_ASSUME_NONNULL_END

@implementation DWContactProfileViewController

+ (instancetype)controllerWithContact:(id<DWContactItem>)contact {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"ContactProfile" bundle:nil];
    DWContactProfileViewController *controller = [storyboard instantiateInitialViewController];
    controller.contact = contact;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // TODO: temp
    self.title = @"Contact";

    self.usernameLabel.text = self.contact.username;

    switch (self.contact.displayType) {
        case DWContactItemDisplayType_Search: {
            self.payButton.hidden = YES;
            self.incomingContactActionsView.hidden = YES;
            self.outgoingStatusLabel.hidden = YES;

            break;
        }
        case DWContactItemDisplayType_Contact: {
            self.incomingContactActionsView.hidden = YES;
            self.outgoingStatusLabel.hidden = YES;

            break;
        }
        case DWContactItemDisplayType_IncomingRequest: {
            self.outgoingStatusLabel.hidden = YES;

            break;
        }
        case DWContactItemDisplayType_OutgoingRequest: {
            self.payButton.hidden = YES;
            self.incomingContactActionsView.hidden = YES;

            break;
        }
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (IBAction)payButtonAction:(id)sender {
    // TODO: set destination from the contact
    DWSendAmountViewController *controller = [DWSendAmountViewController sendControllerWithDestination:@"XqHt831rFj5tr4PVjqEcJmh6VKvHP62QiM" paymentDetails:nil];
    [self.navigationController pushViewController:controller animated:YES];
}

- (IBAction)acceptButtonAction:(id)sender {
}

- (IBAction)declineButtonAction:(id)sender {
}

@end

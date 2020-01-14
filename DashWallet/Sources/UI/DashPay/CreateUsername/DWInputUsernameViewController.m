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

#import "DWInputUsernameViewController.h"

@interface DWInputUsernameViewController () <UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UITextField *textField;

@end

@implementation DWInputUsernameViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"InputUsername" bundle:nil];
    DWInputUsernameViewController *controller = [storyboard instantiateInitialViewController];
    return controller;
}

- (NSString *)text {
    return self.textField.text;
}

- (void)setText:(NSString *)text {
    self.textField.text = text;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    self.textField.text = [self.textField.text stringByReplacingCharactersInRange:range withString:string];
    [self.delegate inputUsernameViewControllerDidUpdateText:self];
    return NO;
}

@end

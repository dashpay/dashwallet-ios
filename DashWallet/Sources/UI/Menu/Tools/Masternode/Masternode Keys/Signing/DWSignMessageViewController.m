//
//  Created by Sam Westrich
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

#import "DWSignMessageViewController.h"
#import <DashSync/DashSync.h>

@interface DWSignMessageViewController ()

@property (strong, nonatomic) IBOutlet UITextView *signatureMessageInputTextView;
@property (strong, nonatomic) IBOutlet UITextView *signatureMessageResultTextView;

@end

@implementation DWSignMessageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (IBAction)sign:(id)sender {
    NSMutableData *stringMessageData = [NSMutableData data];
    [stringMessageData appendString:DASH_MESSAGE_MAGIC];
    [stringMessageData appendString:self.signatureMessageInputTextView.text];
    NSData *data = nil;

    if ([self.key isKindOfClass:[DSBLSKey class]]) {
        DSBLSKey *blsKey = (DSBLSKey *)_key;
        [blsKey signDigest:stringMessageData.SHA256_2];
    }
    else {
        DSECDSAKey *ecdsaKey = (DSECDSAKey *)_key;
        data = [ecdsaKey compactSign:stringMessageData.SHA256_2];
    }

    if (data) {
        [self.signatureMessageResultTextView setText:[data base64EncodedStringWithOptions:0]];
    }
}

@end

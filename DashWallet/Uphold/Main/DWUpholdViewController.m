//  
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWUpholdViewController.h"

#import <SafariServices/SafariServices.h>

#import "DWAppDelegate.h"
#import "DWUpholdClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdViewController ()

@end

@implementation DWUpholdViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdStoryboard" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveURLNotification:)
                                                 name:BRURLNotification
                                               object:nil];
}

#pragma mark - Actions

- (IBAction)linkUpholdAccountButtonAction:(id)sender {
    NSURL *url = [[DWUpholdClient sharedInstance] startAuthRoutineByURL];
    SFSafariViewController *controller = nil;
    if (@available(iOS 11.0, *)) {
        SFSafariViewControllerConfiguration *configuration = [[SFSafariViewControllerConfiguration alloc] init];
        configuration.entersReaderIfAvailable = NO;
        controller = [[SFSafariViewController alloc] initWithURL:url configuration:configuration];
    } else {
        controller = [[SFSafariViewController alloc] initWithURL:url entersReaderIfAvailable:NO];
    }
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)didReceiveURLNotification:(NSNotification *)n {
    NSURL *url = n.userInfo[@"url"];
    if (![url.absoluteString containsString:@"uphold"]) {
        return;
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
    
    __weak typeof(self) weakSelf = self;
    [[DWUpholdClient sharedInstance] completeAuthRoutineWithURL:url completion:^(BOOL success) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        
    }];
}

@end

NS_ASSUME_NONNULL_END

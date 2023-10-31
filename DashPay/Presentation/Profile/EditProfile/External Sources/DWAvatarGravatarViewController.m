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

#import "DWAvatarGravatarViewController.h"

#import <CommonCrypto/CommonDigest.h>
#import <SDWebImage/SDWebImage.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWAvatarGravatarViewController ()

@property (nullable, weak, nonatomic) SDWebImageDownloadToken *token;

@end

NS_ASSUME_NONNULL_END

@implementation NSString (MD5Gravatar)

- (NSString *)dw_MD5String {
    const char *cStr = [self UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), result);

    return [NSString stringWithFormat:
                         @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
                         result[0], result[1], result[2], result[3],
                         result[4], result[5], result[6], result[7],
                         result[8], result[9], result[10], result[11],
                         result[12], result[13], result[14], result[15]];
}

@end

@implementation DWAvatarGravatarViewController

- (DWAvatarExternalSourceConfig *)config {
    DWAvatarExternalSourceConfig *config = [[DWAvatarExternalSourceConfig alloc] init];
    config.icon = [UIImage imageNamed:@"ava_gravatar"];
    config.title = @"Gravatar";
    config.subtitle = NSLocalizedString(@"Enter your Gravatar Email ID", nil);
    config.desc = NSLocalizedString(@"Your Email is not stored in the DashPay wallet nor on any servers. It is used once to get your Gravatar account details and then discarded.", nil);
    config.keyboardType = UIKeyboardTypeEmailAddress;
    config.placeholder = @"example@email.com";
    return config;
}


- (BOOL)isInputValid:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    BOOL valid = trimmed.length > 0 && [self validateEmailWithString:trimmed];
    if (valid) {
        return YES;
    }
    else {
        [self showError:NSLocalizedString(@"Please enter a valid gravatar email ID.", nil)];
        return NO;
    }
}

- (void)performLoad:(NSString *)email {
    [self showLoadingView];

    NSString *trimmed = [email stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // fetch size 200px (s=200) and fail if not found (d=404)
    NSString *urlString = [NSString stringWithFormat:@"https://www.gravatar.com/avatar/%@?s=200&d=404",
                                                     [[trimmed dw_MD5String] lowercaseString]];
    NSURL *url = [NSURL URLWithString:urlString];

    __weak typeof(self) weakSelf = self;
    self.token = [[SDWebImageDownloader sharedDownloader]
        downloadImageWithURL:url
                     options:SDWebImageDownloaderUseNSURLCache
                    progress:nil
                   completed:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
                       __strong typeof(weakSelf) strongSelf = weakSelf;
                       if (!strongSelf) {
                           return;
                       }

                       if (image && finished) {
                           [strongSelf.delegate externalSourceViewController:self didLoadImage:image url:url shouldCrop:NO];
                       }
                       else {
                           [strongSelf showError:NSLocalizedString(@"Unable to fetch your Gravatar. Please enter a valid gravatar email ID.", nil)];
                       }
                   }];
}

- (void)cancelLoading {
    [self.token cancel];
    self.token = nil;

    [self showDefaultSubtitle];
}

- (BOOL)validateEmailWithString:(NSString *)email {
    NSString *emailRegex = @"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,6}$";
    NSPredicate *emailTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", emailRegex];
    return [emailTest evaluateWithObject:email];
}

@end

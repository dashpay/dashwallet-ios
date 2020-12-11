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

#import "DWAvatarPublicURLViewController.h"

#import <SDWebImage/SDWebImage.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWAvatarPublicURLViewController ()

@property (nullable, weak, nonatomic) SDWebImageDownloadToken *token;

@end

NS_ASSUME_NONNULL_END

@implementation DWAvatarPublicURLViewController

- (DWAvatarExternalSourceConfig *)config {
    DWAvatarExternalSourceConfig *config = [[DWAvatarExternalSourceConfig alloc] init];
    config.icon = [UIImage imageNamed:@"ava_puburl"];
    config.title = NSLocalizedString(@"Public URL", nil);
    config.subtitle = NSLocalizedString(@"Paste your image URL", nil);
    config.desc = NSLocalizedString(@"You can specify any URL which is publicly available on the internet so other users can see it on the Dash network.", nil);
    config.keyboardType = UIKeyboardTypeURL;
    return config;
}

- (BOOL)isInputValid:(NSString *)input {
    if (input.length == 0) {
        [self showError:NSLocalizedString(@"Please enter a valid image URL.", nil)];
        return NO;
    }

    const NSUInteger maxLength = 256;
    if (input.length > maxLength) {
        [self showError:[NSString stringWithFormat:NSLocalizedString(@"Image URL can't be longer than %ld characters.", nil), maxLength]];
        return NO;
    }

    // regex to check valid url is too complicated, do a dumb check
    NSURL *url = [NSURL URLWithString:input];
    if (url) {
        return YES;
    }
    else {
        [self showError:NSLocalizedString(@"Please enter a valid image URL.", nil)];
        return NO;
    }
}

- (void)performLoad:(NSString *)urlString {
    [self showLoadingView];

    NSURL *url = [self convertedURLString:urlString];

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
                           [strongSelf.delegate externalSourceViewController:self didLoadImage:image url:url shouldCrop:YES];
                       }
                       else {
                           [strongSelf showError:NSLocalizedString(@"Unable to fetch image. Please enter a valid image URL.", nil)];
                       }
                   }];
}

- (void)cancelLoading {
    [self.token cancel];
    self.token = nil;

    [self showDefaultSubtitle];
}

- (NSURL *)convertedURLString:(NSString *)urlString {
    // https://drive.google.com/file/d/12rhWM7_wIXwDcFfsANkVGa0ArrbnhrMN/view?usp=sharing
    NSString *googlePrefix = @"https://drive.google.com/file/d/";
    if ([urlString hasPrefix:googlePrefix]) {
        NSString *rest = [urlString stringByReplacingOccurrencesOfString:googlePrefix withString:@""];
        NSRange range = [rest rangeOfString:@"/"];
        if (range.location != NSNotFound) {
            NSString *googleID = [rest substringToIndex:range.location];
            NSString *resultFormat = [NSString stringWithFormat:@"https://drive.google.com/uc?export=view&id=%@",
                                                                googleID];
            return [NSURL URLWithString:resultFormat];
        }
    }

    // https://www.dropbox.com/s/2ldd9fjk02yvyv1/IMG_20201103_220114.jpg?dl=0
    NSString *dropboxPrefix = @"https://www.dropbox.com/s/";
    if ([urlString hasPrefix:dropboxPrefix]) {
        NSString *result = [urlString stringByReplacingOccurrencesOfString:dropboxPrefix
                                                                withString:@"https://dl.dropboxusercontent.com/s/"];
        return [NSURL URLWithString:result];
    }

    return [NSURL URLWithString:urlString];
}

@end

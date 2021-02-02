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

#import "DWUploadAvatarModel.h"

#import "DWEnvironment.h"
#import "DWSecrets.h"
#import "UIImage+Utils.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const ImageDeleteHash = @"ImgurImageDeleteHash";

@interface DWUploadAvatarModel ()

@property (nonatomic, assign) DWUploadAvatarModelState state;

@property (atomic, assign) BOOL cancelled;
@property (nullable, nonatomic, copy) NSString *resultURLString;
@property (nullable, weak, nonatomic) id<HTTPLoaderOperationProtocol> uploadOperation;

@end

NS_ASSUME_NONNULL_END

@implementation DWUploadAvatarModel

- (instancetype)initWithImage:(UIImage *)image {
    self = [super init];
    if (self) {
        NSAssert([DWSecrets imgurClientID].length > 0, @"Invalid iCloud key");

        _image = image;

        [self retry];
    }
    return self;
}

- (void)retry {
    self.cancelled = NO;
    self.state = DWUploadAvatarModelState_Loading;

    NSString *deleteHash = [[NSUserDefaults standardUserDefaults] stringForKey:ImageDeleteHash];
    if (deleteHash.length > 0) {
        NSString *urlString = [NSString stringWithFormat:@"https://api.imgur.com/3/image/%@", deleteHash];
        NSURL *url = [NSURL URLWithString:urlString];
        HTTPRequest *request = [HTTPRequest requestWithURL:url method:HTTPRequestMethod_DELETE parameters:nil];
        [request addValue:[NSString stringWithFormat:@"Client-ID %@", [DWSecrets imgurClientID]] forHeader:@"Authorization"];
        request.maximumRetryCount = 3;

        HTTPLoaderManager *loaderManager = [DSNetworkingCoordinator sharedInstance].loaderManager;
        __weak typeof(self) weakSelf = self;
        [loaderManager
            sendRequest:request
             completion:^(id _Nullable parsedData, NSDictionary *_Nullable responseHeaders, NSInteger statusCode, NSError *_Nullable error) {
                 __strong typeof(weakSelf) strongSelf = weakSelf;
                 if (!strongSelf) {
                     return;
                 }

                 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                     [strongSelf upload];
                 });
             }];
    }
    else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self upload];
        });
    }
}

- (void)cancel {
    self.cancelled = YES;
    [self.uploadOperation cancel];
}

- (void)upload {
    if (self.cancelled) {
        return;
    }

    const CGFloat maxImageSide = 600;
    UIImage *resultImage = self.image;
    if (self.image.size.width > maxImageSide || self.image.size.height > maxImageSide) {
        resultImage = [self.image dw_resize:CGSizeMake(maxImageSide, maxImageSide)
                   withInterpolationQuality:kCGInterpolationHigh];
    }

    NSURL *url = [NSURL URLWithString:@"https://api.imgur.com/3/upload"];

    NSString *boundary = [NSUUID UUID].UUIDString;
    NSData *body = [self createBodyWithBoundary:boundary image:resultImage];
    HTTPRequest *request = [[HTTPRequest alloc] initWithURL:url method:HTTPRequestMethod_POST contentType:HTTPContentType_JSON parameters:nil body:body sourceIdentifier:nil];
    [request addValue:[NSString stringWithFormat:@"Client-ID %@", [DWSecrets imgurClientID]]
            forHeader:@"Authorization"];
    [request addValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
            forHeader:@"Content-Type"];

    HTTPLoaderManager *loaderManager = [DSNetworkingCoordinator sharedInstance].loaderManager;

    __weak typeof(self) weakSelf = self;
    self.uploadOperation = [loaderManager
        sendRequest:request
         completion:^(id _Nullable parsedData, NSDictionary *_Nullable responseHeaders, NSInteger statusCode, NSError *_Nullable error) {
             __strong typeof(weakSelf) strongSelf = weakSelf;
             if (!strongSelf) {
                 return;
             }

             if (error) {
                 strongSelf.state = DWUploadAvatarModelState_Error;
             }
             else {
                 NSDictionary *response = (NSDictionary *)parsedData;
                 if ([response[@"success"] boolValue]) {
                     NSDictionary *data = response[@"data"];

                     NSDictionary *deleteHash = data[@"deletehash"];
                     [[NSUserDefaults standardUserDefaults] setObject:deleteHash forKey:ImageDeleteHash];

                     strongSelf.resultURLString = data[@"link"];

                     strongSelf.state = DWUploadAvatarModelState_Success;
                 }
                 else {
                     strongSelf.state = DWUploadAvatarModelState_Error;
                 }
             }
         }];
}

- (NSData *)createBodyWithBoundary:(NSString *)boundary
                             image:(UIImage *)image {
    NSMutableData *httpBody = [NSMutableData data];

    NSString *fieldName = @"image"; // Imgur field

    NSString *filename = @"image.jpg";
    NSData *data = UIImageJPEGRepresentation(image, 0.5);
    NSString *mimetype = @"image/jpeg";

    [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", fieldName, filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", mimetype] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:data];
    [httpBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

    [httpBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    return httpBody;
}

@end

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
#import <CloudKit/CloudKit.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const RecordType = @"DPAvatar";

@interface DWUploadAvatarModel ()

@property (nonatomic, assign) DWUploadAvatarModelState state;

@property (readonly, nonatomic, strong) CKDatabase *database;
@property (readonly, nonatomic, strong) CKRecordID *recordID;

@property (atomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL imageUploaded;
@property (nullable, nonatomic, copy) NSString *resultURLString;
@property (nullable, weak, nonatomic) id<HTTPLoaderOperationProtocol> fetchOperation;


@end

NS_ASSUME_NONNULL_END

@implementation DWUploadAvatarModel

- (instancetype)initWithImage:(UIImage *)image {
    self = [super init];
    if (self) {
        NSAssert([DWSecrets iCloudAPIKey].length > 0, @"Invalid iCloud key");

        _image = image;

        CKContainer *container = [CKContainer containerWithIdentifier:@"iCloud.org.dash.dashwallet"];
        _database = container.publicCloudDatabase;

        DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
        NSParameterAssert(blockchainIdentity);
        _recordID = [[CKRecordID alloc] initWithRecordName:blockchainIdentity.uniqueIdString];

        [self retry];
    }
    return self;
}

- (void)retry {
    self.cancelled = NO;
    self.state = DWUploadAvatarModelState_Loading;

    if (self.imageUploaded) {
        [self fetchURL];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.database deleteRecordWithID:self.recordID
                    completionHandler:^(CKRecordID *_Nullable recordID, NSError *_Nullable error) {
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) {
                            return;
                        }

                        if (error != nil) {
                            DSLogVerbose(@"DPAvatar: delete prev failed: %@", error);
                        }

                        if (strongSelf.cancelled) {
                            return;
                        }

                        [strongSelf upload];
                    }];
}

- (void)cancel {
    self.cancelled = YES;
    self.imageUploaded = NO;
    [self.fetchOperation cancel];
}

- (void)upload {
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    NSString *filePath = [directory stringByAppendingPathComponent:@"dpavatar.jpg"];
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    NSData *imageData = UIImageJPEGRepresentation(self.image, 0.8);
    [imageData writeToFile:filePath atomically:YES];

    CKRecord *record = [[CKRecord alloc] initWithRecordType:RecordType recordID:self.recordID];
    CKAsset *asset = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:filePath]];
    record[@"image"] = asset;

    if (self.cancelled) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.database saveRecord:record
            completionHandler:^(CKRecord *_Nullable record, NSError *_Nullable error) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                if (error != nil) {
                    DSLogVerbose(@"DPAvatar: upload failed: %@", error);

                    dispatch_async(dispatch_get_main_queue(), ^{
                        strongSelf.state = DWUploadAvatarModelState_Error;
                    });

                    return;
                }

                if (strongSelf.cancelled) {
                    return;
                }

                strongSelf.imageUploaded = YES;
                [strongSelf fetchURL];
            }];
}

- (void)fetchURL {
#if DEBUG
    NSString *urlString = [NSString stringWithFormat:
                                        @"https://api.apple-cloudkit.com/database/1/iCloud.org.dash.dashwallet/development/public/records/query?ckAPIToken=%@",
                                        [DWSecrets iCloudAPIKey]];
#else
    NSString *urlString = [NSString stringWithFormat:
                                        @"https://api.apple-cloudkit.com/database/1/iCloud.org.dash.dashwallet/production/public/records/query?ckAPIToken=%@",
                                        [DWSecrets iCloudAPIKey]];
#endif /* DEBUG */
    NSURL *url = [NSURL URLWithString:urlString];

    NSDictionary *query = @{
        @"recordType" : RecordType,
        @"filterBy" : @[
            @{
                @"comparator" : @"EQUALS",
                @"systemFieldName" : @"recordName",
                @"fieldValue" : @{
                    @"value" : @{
                        @"recordName" : self.recordID.recordName,
                    },
                },
            },
        ],
    };


    HTTPRequest *request = [HTTPRequest requestWithURL:url
                                                method:HTTPRequestMethod_POST
                                           contentType:HTTPContentType_JSON
                                            parameters:@{@"query" : query}];
    HTTPLoaderManager *loaderManager = [DSNetworkingCoordinator sharedInstance].loaderManager;

    __weak typeof(self) weakSelf = self;
    self.fetchOperation = [loaderManager
        sendRequest:request
         completion:^(id _Nullable parsedData, NSDictionary *_Nullable responseHeaders, NSInteger statusCode, NSError *_Nullable error) {
             __strong typeof(weakSelf) strongSelf = weakSelf;
             if (!strongSelf) {
                 return;
             }

             strongSelf.fetchOperation = nil;

             if (error) {
                 strongSelf.state = DWUploadAvatarModelState_Error;
             }
             else {
                 NSDictionary *response = (NSDictionary *)parsedData;
                 NSDictionary *record = ((NSArray *)response[@"records"]).firstObject;
                 NSDictionary *fields = record[@"fields"];
                 NSDictionary *image = fields[@"image"];
                 NSDictionary *value = image[@"value"];
                 NSString *fileName = [NSString stringWithFormat:@"%@.jpg", strongSelf.recordID.recordName];
                 NSString *downloadURL = [value[@"downloadURL"] stringByReplacingOccurrencesOfString:@"${f}"
                                                                                          withString:fileName];
                 strongSelf.resultURLString = downloadURL;

                 strongSelf.state = DWUploadAvatarModelState_Success;
             }
         }];
}

@end

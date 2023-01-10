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

#import "DWPayModelStub.h"

#import <CoreNFC/CoreNFC.h>

#import "DWPayOptionModel.h"
#import "DWPaymentInputBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPayModelStub ()

@property (readonly, nonatomic, strong) DWPaymentInputBuilder *inputBuilder;
@property (nullable, nonatomic, strong) DWPaymentInput *pasteboardPaymentInput;

@end

@implementation DWPayModelStub

@synthesize options = _options;

- (instancetype)init {
    self = [super init];
    if (self) {
        _inputBuilder = [[DWPaymentInputBuilder alloc] init];

        NSMutableArray<DWPayOptionModel *> *options = [NSMutableArray array];

        DWPayOptionModel *scanQROption = [[DWPayOptionModel alloc]
            initWithType:DWPayOptionModelType_ScanQR];
        [options addObject:scanQROption];

        DWPayOptionModel *pasteboardOption = [[DWPayOptionModel alloc]
            initWithType:DWPayOptionModelType_Pasteboard];
        [options addObject:pasteboardOption];

        // CoreNFC is optional framework
        Class NFCNDEFReaderSessionClass = NSClassFromString(@"NFCNDEFReaderSession");
        if ([(id)NFCNDEFReaderSessionClass readingAvailable]) {
            DWPayOptionModel *nfcOption = [[DWPayOptionModel alloc]
                initWithType:DWPayOptionModelType_NFC];
            [options addObject:nfcOption];
        }

        _options = [options copy];

        pasteboardOption.details = @"XrUv3aniSvZEKx2VoFe5fTqFfYL5JYFkbg";

        __weak typeof(self) weakSelf = self;
        [_inputBuilder payFirstFromArray:@[ pasteboardOption.details ]
                                  source:DWPaymentInputSource_Pasteboard
                              completion:^(DWPaymentInput *_Nonnull paymentInput) {
                                  __strong typeof(weakSelf) strongSelf = weakSelf;
                                  if (!strongSelf) {
                                      return;
                                  }

                                  strongSelf.pasteboardPaymentInput = paymentInput;
                              }];
    }
    return self;
}

- (void)payToAddressFromPasteboardAvailable:(nonnull void (^)(BOOL))completion {
    completion(true);
}

- (nonnull DWPaymentInput *)paymentInputWithURL:(nonnull NSURL *)url {
    return self.pasteboardPaymentInput;
}

- (DWPaymentInput *)paymentInputWithUser:(id<DWDPBasicUserItem>)userItem {
    return self.pasteboardPaymentInput;
}

- (void)performNFCReadingWithCompletion:(nonnull void (^)(DWPaymentInput *_Nonnull))completion {
}

@end

NS_ASSUME_NONNULL_END

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

NS_ASSUME_NONNULL_BEGIN

@implementation DWPayModelStub

@synthesize options = _options;
@synthesize pasteboardPaymentInput = _pasteboardPaymentInput;

- (instancetype)init {
    self = [super init];
    if (self) {
        NSMutableArray<DWPayOptionModel *> *options = [NSMutableArray array];

        DWPayOptionModel *scanQROption = [[DWPayOptionModel alloc]
            initWithType:DWPayOptionModelType_ScanQR];
        [options addObject:scanQROption];

        DWPayOptionModel *pasteboardOption = [[DWPayOptionModel alloc]
            initWithType:DWPayOptionModelType_Pasteboard];
        [options addObject:pasteboardOption];

        if ([NFCNDEFReaderSession readingAvailable]) {
            DWPayOptionModel *nfcOption = [[DWPayOptionModel alloc]
                initWithType:DWPayOptionModelType_NFC];
            [options addObject:nfcOption];
        }

        _options = [options copy];

        pasteboardOption.details = @"XrUv3aniSvZEKx2VoFe5fTqFfYL5JYFkbg";
    }
    return self;
}

- (void)checkIfPayToAddressFromPasteboardAvailable:(nonnull void (^)(BOOL))completion {
}

- (nonnull DWPaymentInput *)paymentInputWithURL:(nonnull NSURL *)url {
    return self.pasteboardPaymentInput;
}

- (void)performNFCReadingWithCompletion:(nonnull void (^)(DWPaymentInput *_Nonnull))completion {
}

- (void)startPasteboardIntervalObserving {
}

- (void)stopPasteboardIntervalObserving {
}

@end

NS_ASSUME_NONNULL_END

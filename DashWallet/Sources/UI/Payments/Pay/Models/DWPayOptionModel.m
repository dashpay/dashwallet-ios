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

#import "DWPayOptionModel.h"
#import "UIColor+DWStyle.h"
NS_ASSUME_NONNULL_BEGIN

static NSString *TitleForOptionType(DWPayOptionModelType type) {
    switch (type) {
        case DWPayOptionModelType_ScanQR:
            return NSLocalizedString(@"Scan QR code", @"(Send by) Scanning QR code");
        case DWPayOptionModelType_Pasteboard:
            return NSLocalizedString(@"Send to copied address or QR code", nil);
        case DWPayOptionModelType_NFC:
            return NSLocalizedString(@"NFC device", nil);
    }
}

static UIImage *IconForOptionType(DWPayOptionModelType type) {
    UIImage *image = nil;
    switch (type) {
        case DWPayOptionModelType_ScanQR:
            image = [UIImage imageNamed:@"pay_scan_qr"];
            break;
        case DWPayOptionModelType_Pasteboard:
            image = [UIImage imageNamed:@"pay_copied_address"];
            break;
        case DWPayOptionModelType_NFC:
            image = [UIImage imageNamed:@"pay_nfc"];
            break;
    }
    NSCParameterAssert(image);

    return image;
}

@implementation DWPayOptionModel

- (instancetype)initWithType:(DWPayOptionModelType)type {
    self = [super init];
    if (self) {
        _type = type;
    }
    return self;
}

- (UIImage *)icon {
    return IconForOptionType(_type);
}

- (NSString *)title {
    return TitleForOptionType(_type);
}


@end

NS_ASSUME_NONNULL_END

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

#import "UICollectionView+DWDPItemDequeue.h"

#import "DWUIKit.h"

#import "DWDPEstablishedContactItem.h"
#import "DWDPNewIncomingRequestItem.h"
#import "DWDPPendingRequestItem.h"
#import "DWDPRespondedRequestItem.h"

#import "DWDPBasicCell.h"
#import "DWDPImageStatusCell.h"
#import "DWDPIncomingRequestCell.h"
#import "DWDPTextStatusCell.h"

@implementation UICollectionView (DWDPItemDequeue)

- (void)dw_registerDPItemCells {
    [self registerClass:DWDPBasicCell.class forCellWithReuseIdentifier:DWDPBasicCell.dw_reuseIdentifier];
    [self registerClass:DWDPIncomingRequestCell.class forCellWithReuseIdentifier:DWDPIncomingRequestCell.dw_reuseIdentifier];
    [self registerClass:DWDPImageStatusCell.class forCellWithReuseIdentifier:DWDPImageStatusCell.dw_reuseIdentifier];
    [self registerClass:DWDPTextStatusCell.class forCellWithReuseIdentifier:DWDPTextStatusCell.dw_reuseIdentifier];
}

- (__kindof UICollectionViewCell *)dw_dequeueReusableCellForItem:(id<DWDPBasicUserItem>)item atIndexPath:(NSIndexPath *)indexPath {
    // DWDPRespondedRequestItem should come before DWDPIncomingRequestItem since the first one also conforms to DWDPIncomingRequestItem
    NSString *cellID = nil;
    if ([item conformsToProtocol:@protocol(DWDPEstablishedContactItem)]) {
        cellID = DWDPImageStatusCell.dw_reuseIdentifier;
    }
    else if ([item conformsToProtocol:@protocol(DWDPPendingRequestItem)]) {
        cellID = DWDPTextStatusCell.dw_reuseIdentifier;
    }
    else if ([item conformsToProtocol:@protocol(DWDPRespondedRequestItem)]) {
        cellID = DWDPBasicCell.dw_reuseIdentifier;
    }
    else if ([item conformsToProtocol:@protocol(DWDPNewIncomingRequestItem)]) {
        cellID = DWDPIncomingRequestCell.dw_reuseIdentifier;
    }
    else { // any DWDPBasicUserItem
        cellID = DWDPBasicCell.dw_reuseIdentifier;
    }

    return [self dequeueReusableCellWithReuseIdentifier:cellID forIndexPath:indexPath];
}

@end

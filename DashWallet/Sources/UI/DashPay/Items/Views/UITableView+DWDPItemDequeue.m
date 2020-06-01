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

#import "UITableView+DWDPItemDequeue.h"

#import "DWUIKit.h"

#import "DWDPEstablishedContactItem.h"
#import "DWDPIgnoredRequestItem.h"
#import "DWDPIncomingRequestItem.h"
#import "DWDPPendingRequestItem.h"

#import "DWDPBasicCell.h"
#import "DWDPImageStatusCell.h"
#import "DWDPIncomingRequestCell.h"
#import "DWDPTextStatusCell.h"

@implementation UITableView (DWDPItemDequeue)

- (void)dw_registerDPItemCells {
    [self registerClass:DWDPBasicCell.class forCellReuseIdentifier:DWDPBasicCell.dw_reuseIdentifier];
    [self registerClass:DWDPIncomingRequestCell.class forCellReuseIdentifier:DWDPIncomingRequestCell.dw_reuseIdentifier];
    [self registerClass:DWDPImageStatusCell.class forCellReuseIdentifier:DWDPImageStatusCell.dw_reuseIdentifier];
    [self registerClass:DWDPTextStatusCell.class forCellReuseIdentifier:DWDPTextStatusCell.dw_reuseIdentifier];
}

- (__kindof UITableViewCell *)dw_dequeueReusableCellForItem:(id<DWDPBasicItem>)item atIndexPath:(NSIndexPath *)indexPath {
    // DWDPIgnoredRequestItem should come before DWDPIncomingRequestItem since the first one also conforms to DWDPIncomingRequestItem
    NSString *cellID = nil;
    if ([item conformsToProtocol:@protocol(DWDPEstablishedContactItem)]) {
        cellID = DWDPImageStatusCell.dw_reuseIdentifier;
    }
    else if ([item conformsToProtocol:@protocol(DWDPPendingRequestItem)]) {
        cellID = DWDPTextStatusCell.dw_reuseIdentifier;
    }
    else if ([item conformsToProtocol:@protocol(DWDPIgnoredRequestItem)]) {
        cellID = DWDPBasicCell.dw_reuseIdentifier;
    }
    else if ([item conformsToProtocol:@protocol(DWDPIncomingRequestItem)]) {
        cellID = DWDPIncomingRequestCell.dw_reuseIdentifier;
    }
    else { // any DWDPBasicItem
        cellID = DWDPBasicCell.dw_reuseIdentifier;
    }

    return [self dequeueReusableCellWithIdentifier:cellID forIndexPath:indexPath];
}

@end

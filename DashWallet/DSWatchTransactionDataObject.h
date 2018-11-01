//
//  DSWatchTransactionDataObject.h
//  dashwallet
//
//  Created by Andrew Podkovyrin on 30/10/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <DashSync/DashSync.h>
#import "DSWatchTransactionData.h"

NS_ASSUME_NONNULL_BEGIN

@interface DSWatchTransactionDataObject : NSObject <DSWatchTransactionData>

- (nullable instancetype)initWithTransaction:(DSTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END

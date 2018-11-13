//
//  DSWatchTransactionData.h
//  dashwallet
//
//  Created by Andrew Podkovyrin on 30/10/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSInteger {
    BRAWTransactionTypeSent,
    BRAWTransactionTypeReceive,
    BRAWTransactionTypeMove,
    BRAWTransactionTypeInvalid
} BRAWTransactionType;

@protocol DSWatchTransactionData <NSObject>

@property (readonly, nonatomic, copy) NSString *amountText;
@property (readonly, nonatomic, copy) NSString *amountTextInLocalCurrency;
@property (readonly, nonatomic, copy) NSString *dateText;
@property (readonly, assign, nonatomic) BRAWTransactionType type;

@end

NS_ASSUME_NONNULL_END

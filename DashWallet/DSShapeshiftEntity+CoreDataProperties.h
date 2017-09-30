//
//  DSShapeshiftEntity+CoreDataProperties.h
//  BreadWallet
//
//  Created by Sam Westrich on 1/31/17.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//

#import "DSShapeshiftEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@class BRTransactionEntity;

@interface DSShapeshiftEntity (CoreDataProperties)

+ (NSFetchRequest<DSShapeshiftEntity *> *)fetchRequest;

@property (nullable, nonatomic, copy) NSString *errorMessage;
@property (nullable, nonatomic, copy) NSDate *expiresAt;
@property (nullable, nonatomic, copy) NSString *inputAddress;
@property (nullable, nonatomic, copy) NSNumber *inputCoinAmount;
@property (nullable, nonatomic, copy) NSString *inputCoinType;
@property (nullable, nonatomic, copy) NSNumber *isFixedAmount;
@property (nullable, nonatomic, copy) NSNumber *outputCoinAmount;
@property (nullable, nonatomic, copy) NSString *outputCoinType;
@property (nullable, nonatomic, copy) NSString *outputTransactionId;
@property (nullable, nonatomic, copy) NSNumber *shapeshiftStatus;
@property (nullable, nonatomic, copy) NSString *withdrawalAddress;
@property (nullable, nonatomic, retain) BRTransactionEntity *transaction;

@end

NS_ASSUME_NONNULL_END

//
//  DSShapeshiftEntity+CoreDataProperties.h
//  DashSync
//
//  Created by Sam Westrich on 1/31/17.
//  Copyright © 2018 Dash Core. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "DSShapeshiftEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@class DSTransactionEntity;

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
@property (nullable, nonatomic, retain) DSTransactionEntity *transaction;

@end

NS_ASSUME_NONNULL_END

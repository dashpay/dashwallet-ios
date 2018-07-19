//
//  DSShapeshiftEntity+CoreDataClass.h
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

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

typedef enum eShapeshiftAddressStatus {
    eShapeshiftAddressStatus_Unused = 0,
    eShapeshiftAddressStatus_NoDeposits = 1,
    eShapeshiftAddressStatus_Received = 2,
    eShapeshiftAddressStatus_Complete = 4,
    eShapeshiftAddressStatus_Failed = 8,
    eShapeshiftAddressStatus_Finished = eShapeshiftAddressStatus_Complete | eShapeshiftAddressStatus_Failed,
} eShapeshiftAddressStatus;

NS_ASSUME_NONNULL_BEGIN

@interface DSShapeshiftEntity : NSManagedObject

-(NSString*)shapeshiftStatusString;

-(void)checkStatus;

+(NSArray*)shapeshiftsInProgress;

+(DSShapeshiftEntity*)shapeshiftHavingWithdrawalAddress:(NSString*)withdrawalAddress;
+(DSShapeshiftEntity*)unusedShapeshiftHavingWithdrawalAddress:(NSString*)withdrawalAddress;
+(DSShapeshiftEntity*)registerShapeshiftWithInputAddress:(NSString*)inputAddress andWithdrawalAddress:(NSString*)withdrawalAddress withStatus:(eShapeshiftAddressStatus)shapeshiftAddressStatus;
+(DSShapeshiftEntity*)registerShapeshiftWithInputAddress:(NSString*)inputAddress andWithdrawalAddress:(NSString*)withdrawalAddress withStatus:(eShapeshiftAddressStatus)shapeshiftAddressStatus fixedAmountOut:(NSNumber*)amountOut amountIn:(NSNumber*)amountIn;

-(void)routinelyCheckStatusAtInterval:(NSTimeInterval)timeInterval;

@end

NS_ASSUME_NONNULL_END



#import "DSShapeshiftEntity+CoreDataProperties.h"

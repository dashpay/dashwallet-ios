//
//  DSShapeshiftEntity+CoreDataClass.h
//  BreadWallet
//
//  Created by Sam Westrich on 1/31/17.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//

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

//
//  DSShapeshiftManager.h
//  DashWallet
//
//  Created by Quantum Explorer on 7/14/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DSShapeshiftManager : NSObject

#define CURRENT_SHIFT_DEPOSIT_ADDRESS @"currentShiftDepositAddress"
#define CURRENT_SHIFT_WITHDRAWAL_ADDRESS @"currentShiftWithdrawalAddress"

@property (nonatomic,strong) NSDate * lastMarketInfoCheck;
@property (nonatomic,assign) double rate;
@property (nonatomic,assign) unsigned long long limit;
@property (nonatomic,assign) unsigned long long min;

+ (instancetype)sharedInstance;


-(void)GET_marketInfo:(void (^)(NSDictionary *marketInfo, NSError *error))completionBlock;

-(void)POST_ShiftWithAddress:(NSString*)withdrawalAddress returnAddress:(NSString*)returnAddress completionBlock:(void (^)(NSDictionary *shiftInfo, NSError *error))completionBlock;

-(void)POST_CancelShiftToAddress:(NSString*)withdrawalAddress completionBlock:(void (^)(NSDictionary *shiftInfo, NSError *error))completionBlock;

-(void)POST_SendAmount:(NSNumber*)amount withAddress:(NSString*)withdrawalAddress returnAddress:(NSString*)returnAddress completionBlock:(void (^)(NSDictionary *shiftInfo, NSError *error))completionBlock;

-(void)POST_RequestEmailReceiptOfShapeshiftWithOutputTransactionId:(NSString*)shapeshiftOutputTransactionId toEmailAddress:(NSString*)validEmailAddress completionBlock:(void (^)(NSDictionary *shiftInfo, NSError *error))completionBlock;

-(void)GET_transactionStatusWithAddress:(NSString*)withdrawalAddress completionBlock:(void (^)(NSDictionary *transactionInfo, NSError *error))completionBlock;

@end

//
//  DSShapeshiftEntity+CoreDataClass.m
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
#import "DSTransactionEntity+CoreDataClass.h"
#import "NSManagedObject+Sugar.h"
#import "DSShapeshiftManager.h"
#import "DSChainPeerManager.h"
#import "DSChain.h"
#import "DSChainManager.h"

@interface DSShapeshiftEntity()

@property(atomic,assign) BOOL checkingStatus;
@property (nonatomic, strong) NSTimer * checkStatusTimer;

@end

@implementation DSShapeshiftEntity

@synthesize checkingStatus;
@synthesize checkStatusTimer;

-(NSString*)shapeshiftStatusString {
    switch ([self.shapeshiftStatus integerValue]) {
        case eShapeshiftAddressStatus_Complete:
            return @"Completed";
            break;
        case eShapeshiftAddressStatus_Failed:
            return self.errorMessage;
            break;
        case eShapeshiftAddressStatus_Unused:
            return @"Started Shapeshift";
            break;
        case eShapeshiftAddressStatus_NoDeposits:
            return @"Shapeshift Depositing";
            break;
        case eShapeshiftAddressStatus_Received:
            return @"Shapeshift in Progress";
            break;
        default:
            return @"Unknown";
    }
}

+(DSShapeshiftEntity*)shapeshiftHavingWithdrawalAddress:(NSString*)withdrawalAddress {
    DSShapeshiftEntity * previousShapeshift = [DSShapeshiftEntity anyObjectMatching:@"withdrawalAddress == %@",withdrawalAddress];
    return previousShapeshift;
}

+(DSShapeshiftEntity*)unusedShapeshiftHavingWithdrawalAddress:(NSString*)withdrawalAddress {
    DSShapeshiftEntity * previousShapeshift = [DSShapeshiftEntity anyObjectMatching:@"withdrawalAddress == %@ && shapeshiftStatus == %@",withdrawalAddress, @(eShapeshiftAddressStatus_Unused)];
    return previousShapeshift;
}

+(DSShapeshiftEntity*)registerShapeshiftWithInputAddress:(NSString*)inputAddress andWithdrawalAddress:(NSString*)withdrawalAddress withStatus:(eShapeshiftAddressStatus)shapeshiftAddressStatus{
    DSShapeshiftEntity * shapeshift = [DSShapeshiftEntity managedObject];
    shapeshift.inputAddress = inputAddress;
    shapeshift.withdrawalAddress = withdrawalAddress;
    shapeshift.shapeshiftStatus = @(shapeshiftAddressStatus);
    shapeshift.isFixedAmount = @NO;
    [self saveContext];
    return shapeshift;
}

+(DSShapeshiftEntity*)registerShapeshiftWithInputAddress:(NSString*)inputAddress andWithdrawalAddress:(NSString*)withdrawalAddress withStatus:(eShapeshiftAddressStatus)shapeshiftAddressStatus fixedAmountOut:(NSNumber*)amountOut amountIn:(NSNumber*)amountIn {
    DSShapeshiftEntity * shapeshift = [DSShapeshiftEntity managedObject];
    shapeshift.inputAddress = inputAddress;
    shapeshift.withdrawalAddress = withdrawalAddress;
    shapeshift.outputCoinAmount = amountOut;
    shapeshift.inputCoinAmount = amountIn;
    shapeshift.shapeshiftStatus = @(shapeshiftAddressStatus);
    shapeshift.isFixedAmount = @YES;
    shapeshift.expiresAt = [NSDate dateWithTimeIntervalSinceNow:540];  //9 minutes (leave 1 minute as buffer)
    [self saveContext];
    return shapeshift;
}

+(NSArray*)shapeshiftsInProgress {
    static uint32_t height = 0;
    DSChainPeerManager * manager = [[DSChainManager sharedInstance] mainnetManager];
    uint32_t h = [[manager chain] lastBlockHeight];
    if (h > 20) height = h - 20; //only care about shapeshifts in last 20 blocks
    NSArray * shapeshiftsInProgress = [DSShapeshiftEntity objectsMatching:@"(shapeshiftStatus == %@ || shapeshiftStatus == %@) && transaction.blockHeight > %@",@(eShapeshiftAddressStatus_NoDeposits), @(eShapeshiftAddressStatus_Received),@(height)];
    
    return shapeshiftsInProgress;
}

-(void)checkStatus {
    if (self.checkingStatus) {
        return;
    }
    self.checkingStatus = TRUE;
    [[DSShapeshiftManager sharedInstance] GET_transactionStatusWithAddress:self.inputAddress completionBlock:^(NSDictionary *transactionInfo, NSError *error) {
        self.checkingStatus = FALSE;
        if (transactionInfo) {
            NSString * status = transactionInfo[@"status"];
            if ([status isEqualToString:@"received"]) {
                if ([self.shapeshiftStatus integerValue] != eShapeshiftAddressStatus_Received)
                    self.shapeshiftStatus = @(eShapeshiftAddressStatus_Received);
                self.inputCoinAmount = transactionInfo[@"incomingCoin"];
                id inputCoinAmount = transactionInfo[@"incomingCoin"];
                if ([inputCoinAmount isKindOfClass:[NSNumber class]]) {
                    self.inputCoinAmount = inputCoinAmount;
                } else if ([inputCoinAmount isKindOfClass:[NSString class]]) {
                    self.inputCoinAmount = @([inputCoinAmount doubleValue]);
                }
                [DSShapeshiftEntity saveContext];
            } else if ([status isEqualToString:@"complete"]) {
                self.shapeshiftStatus = @(eShapeshiftAddressStatus_Complete);
                self.outputTransactionId = transactionInfo[@"transaction"];
                id inputCoinAmount = transactionInfo[@"incomingCoin"];
                if ([inputCoinAmount isKindOfClass:[NSNumber class]]) {
                    self.inputCoinAmount = inputCoinAmount;
                } else if ([inputCoinAmount isKindOfClass:[NSString class]]) {
                    self.inputCoinAmount = @([inputCoinAmount doubleValue]);
                }
                self.inputCoinAmount = transactionInfo[@"incomingCoin"];
                id outputCoinAmount = transactionInfo[@"outgoingCoin"];
                if ([outputCoinAmount isKindOfClass:[NSNumber class]]) {
                    self.outputCoinAmount = outputCoinAmount;
                } else if ([outputCoinAmount isKindOfClass:[NSString class]]) {
                    self.outputCoinAmount = @([outputCoinAmount doubleValue]);
                }
                [DSShapeshiftEntity saveContext];
                [self.checkStatusTimer invalidate];
            } else if ([status isEqualToString:@"failed"]) {
                self.shapeshiftStatus = @(eShapeshiftAddressStatus_Failed);
                self.errorMessage = transactionInfo[@"error"];
                [DSShapeshiftEntity saveContext];
                [self.checkStatusTimer invalidate];
            }
        }
    }];
}

-(void)routinelyCheckStatusAtInterval:(NSTimeInterval)timeInterval {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.checkStatusTimer) {
            [self.checkStatusTimer invalidate];
        }
        self.checkStatusTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval target:self selector:@selector(checkStatus) userInfo:nil repeats:YES];
    });
}

-(void)deleteObject {
    [self.checkStatusTimer invalidate];
    [super deleteObject];
}

@end


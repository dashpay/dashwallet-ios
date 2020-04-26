//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DWPaymentInput;
@class DWPaymentProcessor;
@class DSPaymentProtocolDetails;
@class DSPaymentProtocolRequest;
@class DSPaymentRequest;
@class DSTransaction;
@class DWPaymentOutput;

@protocol DWPaymentProcessorDelegate <NSObject>

// User Actions

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    requestAmountWithDestination:(NSString *)sendingDestination
                         details:(nullable DSPaymentProtocolDetails *)details;

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    requestUserActionTitle:(nullable NSString *)title
                   message:(nullable NSString *)message
               actionTitle:(NSString *)actionTitle
               cancelBlock:(void (^)(void))cancelBlock
               actionBlock:(void (^)(void))actionBlock;

// Confirmation

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    confirmPaymentOutput:(DWPaymentOutput *)paymentOutput;

- (void)paymentProcessorDidCancelTransactionSigning:(DWPaymentProcessor *)processor;

// Result

- (void)paymentProcessor:(DWPaymentProcessor *)processor
        didFailWithError:(nullable NSError *)error
                   title:(nullable NSString *)title
                 message:(nullable NSString *)message;

- (void)paymentProcessor:(DWPaymentProcessor *)processor
          didSendRequest:(DSPaymentProtocolRequest *)protocolRequest
             transaction:(DSTransaction *)transaction;

- (void)paymentProcessor:(DWPaymentProcessor *)processor
         didSweepRequest:(DSPaymentRequest *)protocolRequest
             transaction:(DSTransaction *)transaction;

// Handle File

- (void)paymentProcessor:(DWPaymentProcessor *)processor displayFileProcessResult:(NSString *)result;
- (void)paymentProcessorDidFinishProcessingFile:(DWPaymentProcessor *)processor;

// Progress HUD

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    showProgressHUDWithMessage:(nullable NSString *)message;
- (void)paymentInputProcessorHideProgressHUD:(DWPaymentProcessor *)processor;

@end

// Refactored version of old DWSendViewController logic

@interface DWPaymentProcessor : NSObject

- (void)processPaymentInput:(DWPaymentInput *)paymentInput;
- (void)processFile:(NSData *)file;

- (void)provideAmount:(uint64_t)amount;

- (void)confirmPaymentOutput:(DWPaymentOutput *)paymentOutput;

- (instancetype)initWithDelegate:(id<DWPaymentProcessorDelegate>)delegate;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

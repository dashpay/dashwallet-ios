//
//  BRSharedContainerManager.m
//  BreadWallet
//
//  Created by Henry Tsai on 6/13/15.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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

#import "BRAppGroupManager.h"
#import "BRWallet.h"
#import "BRPaymentRequest.h"
#import "BRWalletManager.h"
#import "NSUserDefaults+AppGroup.h"
#import "BRAppGroupConstants.h"

@interface BRAppGroupManager ()
@end

@implementation BRAppGroupManager

- (instancetype)init {
	if (self = [super init]) {
		[self copyDataToNSUserDefaultInSharedContainer];
		[self setupObserver];
	}
	return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupObserver {
    [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
             [self copyDataToNSUserDefaultInSharedContainer];
     }];
}


#pragma mark - move data methods

- (void)copyDataToNSUserDefaultInSharedContainer {
    BRPaymentRequest *paymentRequest = [self paymentRequestFromWallet];
    NSString *receiveAddress = [[[BRWalletManager sharedInstance] wallet] receiveAddress];
    if (paymentRequest) {
        [[NSUserDefaults appGroupUserDefault] setObject:paymentRequest.data forKey:kBRSharedContainerDataWalletRequestDataKey];
    } else {
        [[NSUserDefaults appGroupUserDefault] removeObjectForKey:kBRSharedContainerDataWalletRequestDataKey];
    }
    if (receiveAddress) {
        [[NSUserDefaults appGroupUserDefault] setObject:receiveAddress forKey:kBRSharedContainerDataWalletReceiveAddressKey];
    } else {
        [[NSUserDefaults appGroupUserDefault] removeObjectForKey:kBRSharedContainerDataWalletReceiveAddressKey];
    }
    [[NSUserDefaults appGroupUserDefault] synchronize];
}

- (BRPaymentRequest *)paymentRequestFromWallet {
    NSString *receiveAddress = [[[BRWalletManager sharedInstance] wallet] receiveAddress];
    BRPaymentRequest *paymentRequest = [BRPaymentRequest requestWithString:receiveAddress];
    if (!paymentRequest.isValid) {
        paymentRequest = nil;
    }
    return paymentRequest;
}

@end

//
//  DWVersionManager.h
//  dashwallet
//
//  Created by Sam Westrich on 11/2/18.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import <Foundation/Foundation.h>

#define SHOWED_WARNING_FOR_INCOMPLETE_PASSPHRASE @"SHOWED_WARNING_FOR_INCOMPLETE_PASSPHRASE"

NS_ASSUME_NONNULL_BEGIN

typedef void (^CheckPassphraseCompletionBlock)(BOOL needsCheck,BOOL authenticated,BOOL cancelled,NSString * _Nullable seedPhrase);

@interface DWVersionManager : NSObject

+ (instancetype _Nullable)sharedInstance;

- (void)checkPassphraseWasShownCorrectlyForWallet:(DSWallet*)wallet withCompletion:(CheckPassphraseCompletionBlock)completion;

@end

NS_ASSUME_NONNULL_END

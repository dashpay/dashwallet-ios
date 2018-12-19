//
//  DWEnvironment.h
//  DashWallet
//
//  Created by Sam Westrich on 10/25/18.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import <Foundation/Foundation.h>

#define WALLET_NEEDS_BACKUP_KEY @"WALLET_NEEDS_BACKUP"

NS_ASSUME_NONNULL_BEGIN

@interface DWEnvironment : NSObject

@property (nonatomic,strong,nonnull) DSChain * currentChain;
@property (nonatomic,readonly) DSWallet * currentWallet;
@property (nonatomic,readonly) DSAccount * currentAccount;
@property (nonatomic,strong) DSChainManager * currentChainManager;

+ (instancetype _Nullable)sharedInstance;
- (void)clearWallet;
- (void)switchToMainnetWithCompletion:(void (^)(BOOL success))completion;
- (void)switchToTestnetWithCompletion:(void (^)(BOOL success))completion;
-(void)reset;

@end

NS_ASSUME_NONNULL_END

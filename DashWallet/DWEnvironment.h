//
//  DWEnvironment.h
//  DashWallet
//
//  Created by Sam Westrich on 10/25/18.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWEnvironment : NSObject

@property (nonatomic,strong) DSChain * currentChain;
@property (nonatomic,strong) DSWallet * currentWallet;
@property (nonatomic,strong) DSAccount * currentAccount;
@property (nonatomic,strong) DSChainPeerManager * currentChainPeerManager;

+ (instancetype _Nullable)sharedInstance;
- (instancetype)clearWallet;

@end

NS_ASSUME_NONNULL_END

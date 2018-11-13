//
//  DWDataMigrationManager.h
//  dashwallet
//
//  Created by Andrew Podkovyrin on 08/11/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWDataMigrationManager : NSObject

@property (readonly, assign, nonatomic) BOOL shouldMigrate;

+ (instancetype)sharedInstance;

- (void)migrate:(void (^)(BOOL completed))completion;

@end

NS_ASSUME_NONNULL_END

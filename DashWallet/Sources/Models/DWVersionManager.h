//
//  DWVersionManager.h
//  dashwallet
//
//  Created by Sam Westrich on 11/2/18.
//  Copyright © 2019 Dash Core. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWVersionManager : NSObject

+ (instancetype)sharedInstance;

- (void)migrateUserDefaults;

@end

NS_ASSUME_NONNULL_END

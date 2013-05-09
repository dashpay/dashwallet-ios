//
//  ZNAppDelegate.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>

@interface ZNAppDelegate : UIResponder <UIApplicationDelegate, CBCentralManagerDelegate>

@property (strong, nonatomic) UIWindow *window;

@end

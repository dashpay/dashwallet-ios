//
//  ZNFirstViewController.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <GameKit/GameKit.h>
#import "ZBarReaderController.h"

@interface ZNPayViewController : UIViewController <GKSessionDelegate, UIAlertViewDelegate, ZBarReaderDelegate>

@end

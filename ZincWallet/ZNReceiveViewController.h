//
//  ZNSecondViewController.h
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <UIKit/UIKit.h>
//#import <GameKit/GameKit.h>
#import <MessageUI/MessageUI.h>

@interface ZNReceiveViewController : UIViewController <UIActionSheetDelegate, //UITextFieldDelegate, GKSessionDelegate,
MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate>

@property (nonatomic, strong) UINavigationController *navController;
@property (nonatomic, readonly) NSString *copiedAddress; // exclude this address from pay to clipboard address

@end

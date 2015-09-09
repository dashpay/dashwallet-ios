//
//  BREventConfirmView.h
//  BreadWallet
//
//  Created by Samuel Sutch on 9/9/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface BREventConfirmView : UIImageView

@property (nonatomic, copy) void(^completionHandler)(BOOL);

@end

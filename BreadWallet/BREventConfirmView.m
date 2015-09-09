//
//  BREventConfirmView.m
//  BreadWallet
//
//  Created by Samuel Sutch on 9/9/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import "BREventConfirmView.h"

@interface BREventConfirmView ()

- (IBAction)confirm:(id)sender;
- (IBAction)deny:(id)sender;

@end

@implementation BREventConfirmView

- (void)confirm:(id)sender
{
    if (self.completionHandler) {
        self.completionHandler(YES);
    }
}

- (void)deny:(id)sender
{
    if (self.completionHandler) {
        self.completionHandler(NO);
    }
}

@end

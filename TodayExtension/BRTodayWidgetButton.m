//
//  BRTodayWidgetButton.m
//  BreadWallet
//
//  Created by Henry on 6/16/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import "BRTodayWidgetButton.h"

@implementation BRTodayWidgetButton

-(void) setHighlighted:(BOOL)highlighted {
    if(highlighted) {
        self.backgroundColor = [UIColor blackColor];
    } else {
        self.backgroundColor = [UIColor whiteColor];
    }
    [super setHighlighted:highlighted];
}

@end

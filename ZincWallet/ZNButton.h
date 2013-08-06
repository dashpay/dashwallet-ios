//
//  ZNButton.h
//  ZincWallet
//
//  Created by Aaron Voisine on 6/14/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef enum {
    ZNButtonStyleWhite,
    ZNButtonStyleBlue,
    ZNButtonStyleGray
} ZNButtonStyle;

@interface ZNButton : UIButton

- (void)setStyle:(ZNButtonStyle)style;

@end

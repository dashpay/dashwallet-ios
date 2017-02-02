//
//  NSAttributedString+Attachments.h
//  DashWallet
//
//  Created by Quantum Explorer on 8/13/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSAttributedString (Attachments)

- (NSArray *)allAttachments;
- (NSTextAttachment *)firstAttachment;

@end

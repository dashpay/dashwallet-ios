//
//  NSAttributedString+Attachments.m
//  DashWallet
//
//  Created by Quantum Explorer on 8/13/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import "NSAttributedString+Attachments.h"

@implementation NSAttributedString (Attachments)

- (NSArray *)allAttachments
{
    NSMutableArray *theAttachments = [NSMutableArray array];
    NSRange theStringRange = NSMakeRange(0, [self length]);
    if (theStringRange.length > 0)
    {
        unsigned n = 0;
        do
        {
            NSRange theEffectiveRange;
            NSDictionary *theAttributes = [self attributesAtIndex:n longestEffectiveRange:&theEffectiveRange inRange:theStringRange];
            NSTextAttachment *theAttachment = [theAttributes objectForKey:NSAttachmentAttributeName];
            if (theAttachment)
                [theAttachments addObject:theAttachment];
            n = theEffectiveRange.location + theEffectiveRange.length;
        }
        while (n < theStringRange.length);
    }
    return(theAttachments);
}


- (NSTextAttachment *)firstAttachment {
    NSRange theStringRange = NSMakeRange(0, [self length]);
    if (theStringRange.length > 0)
    {
        unsigned n = 0;
        do
        {
            NSRange theEffectiveRange;
            NSDictionary *theAttributes = [self attributesAtIndex:n longestEffectiveRange:&theEffectiveRange inRange:theStringRange];
            NSTextAttachment *theAttachment = [theAttributes objectForKey:NSAttachmentAttributeName];
            if (theAttachment)
                return theAttachment;
            n = theEffectiveRange.location + theEffectiveRange.length;
        }
        while (n < theStringRange.length);
    }
    return nil;
}

@end

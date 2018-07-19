//
//  NSAttributedString+Attachments.m
//  DashSync
//
//  Created by Quantum Explorer on 8/13/15.
//  Copyright (c) 2015 Quantum Explorer. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import <UIKit/UIKit.h>
#import "NSAttributedString+Attachments.h"

@implementation NSAttributedString (Attachments)

- (NSArray *)allAttachments
{
    NSMutableArray *theAttachments = [NSMutableArray array];
    NSRange theStringRange = NSMakeRange(0, [self length]);
    if (theStringRange.length > 0)
    {
        unsigned long n = 0;
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
        unsigned long n = 0;
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

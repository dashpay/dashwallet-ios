//
//  ZNStoryBoardSegue.m
//  ZincWallet
//
//  Created by Aaron Voisine on 9/11/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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

#import "ZNStoryboardSegue.h"

@implementation ZNStoryboardSegue

- (void)perform
{
    CGPoint p = [[self.destinationViewController view] center];
    
    p.x += [[self.destinationViewController view] frame].size.width;
    [[self.destinationViewController view] setCenter:p];
    [[[self.sourceViewController view] superview] addSubview:[self.destinationViewController view]];

    if ([[[self.sourceViewController navigationController] delegate]
         respondsToSelector:@selector(navigationController:willShowViewController:animated:)]) {
        [[[self.sourceViewController navigationController] delegate]
         navigationController:[self.sourceViewController navigationController]
         willShowViewController:self.destinationViewController animated:YES];
    }

    [UIView animateWithDuration:SEGUE_DURATION animations:^{
        CGPoint p = [[self.sourceViewController view] center];
        
        p.x -= [[self.sourceViewController view] frame].size.width;
        [[self.sourceViewController view] setCenter:p];
        
        p.x += [[self.sourceViewController view] frame].size.width;
        [[self.destinationViewController view] setCenter:p];
    } completion:^(BOOL finished) {
        [[self.sourceViewController navigationController] pushViewController:self.destinationViewController animated:NO];
        
        if ([[[self.sourceViewController navigationController] delegate]
             respondsToSelector:@selector(navigationController:didShowViewController:animated:)]) {
            [[[self.sourceViewController navigationController] delegate]
             navigationController:[self.sourceViewController navigationController]
             didShowViewController:self.destinationViewController animated:YES];
        }
    }];
}

@end

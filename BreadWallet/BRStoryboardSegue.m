//
//  BRStoryBoardSegue.m
//  BreadWallet
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

#import "BRStoryboardSegue.h"

@implementation BRStoryboardSegue

+ (void)segueFrom:(UIViewController *)from to:(UIViewController *)to completion:(void (^)())completion
{
    to.view.center = CGPointMake(to.view.center.x + to.view.frame.size.width, to.view.center.y);
    [from.view.superview addSubview:to.view];
    
    if ([from.navigationController.delegate
         respondsToSelector:@selector(navigationController:willShowViewController:animated:)]) {
        [from.navigationController.delegate navigationController:from.navigationController willShowViewController:to
         animated:YES];
    }
    
    [UIView animateWithDuration:SEGUE_DURATION animations:^{
        from.navigationController.navigationBar.alpha = 0.5;
        to.view.center = from.view.center;
        from.view.center = CGPointMake(from.view.center.x - from.view.frame.size.width, from.view.center.y);
    } completion:^(BOOL finished) {
        [from.navigationController pushViewController:to animated:NO];
        
        [UIView animateWithDuration:0.1 animations:^{
            from.navigationController.navigationBar.alpha = 1.0;
        }];

        if ([from.navigationController.delegate
             respondsToSelector:@selector(navigationController:didShowViewController:animated:)]) {
            [from.navigationController.delegate navigationController:from.navigationController didShowViewController:to
             animated:YES];
        }
        
        if (completion) completion();
    }];
}

- (void)perform
{
    [[self class] segueFrom:self.sourceViewController to:self.destinationViewController completion:nil];
}

@end

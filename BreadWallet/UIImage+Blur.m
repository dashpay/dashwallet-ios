//
//  UIImage+Blur.m
//  BreadWallet
//
//  Created by Aaron Voisine on 11/8/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
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

#import "UIImage+Blur.h"
#import <Accelerate/Accelerate.h>

@implementation UIImage (Blur)

- (UIImage *)blurWithRadius:(CGFloat)radius
{
    UIGraphicsBeginImageContext(self.size);

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect rect = { CGPointZero, self.size };
    uint32_t r = floor(radius*[[UIScreen mainScreen] scale]*3.0*sqrt(2.0*M_PI)/4.0 + 0.5);
    
    CGContextScaleCTM(context, 1.0, -1.0);
    CGContextTranslateCTM(context, 0.0, -self.size.height);
    CGContextDrawImage(context, rect, self.CGImage);

    vImage_Buffer inbuf = {
        CGBitmapContextGetData(context),
        CGBitmapContextGetHeight(context),
        CGBitmapContextGetWidth(context),
        CGBitmapContextGetBytesPerRow(context)
    };
    
    UIGraphicsBeginImageContext(self.size);
    context = UIGraphicsGetCurrentContext();
    
    vImage_Buffer outbuf = {
        CGBitmapContextGetData(context),
        CGBitmapContextGetHeight(context),
        CGBitmapContextGetWidth(context),
        CGBitmapContextGetBytesPerRow(context)
    };

    if (r % 2 == 0) r++; // make sure radius is odd for three box-blur method
    vImageBoxConvolve_ARGB8888(&inbuf, &outbuf, NULL, 0, 0, r, r, 0, kvImageEdgeExtend);
    vImageBoxConvolve_ARGB8888(&outbuf, &inbuf, NULL, 0, 0, r, r, 0, kvImageEdgeExtend);
    vImageBoxConvolve_ARGB8888(&inbuf, &outbuf, NULL, 0, 0, r, r, 0, kvImageEdgeExtend);

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    UIGraphicsBeginImageContext(self.size);
    context = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(context, 1.0, -1.0);
    CGContextTranslateCTM(context, 0.0, -self.size.height);
    CGContextDrawImage(context, rect, self.CGImage); // draw base image
    CGContextSaveGState(context);
    CGContextDrawImage(context, rect, img.CGImage); // draw effect image
    CGContextRestoreGState(context);
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end

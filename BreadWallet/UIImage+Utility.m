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

#import "UIImage+Utility.h"
#import <Accelerate/Accelerate.h>

@implementation UIImage (Blur)

- (UIImage *)blurWithRadius:(CGFloat)radius {
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

+ (instancetype)imageWithQRCodeData:(NSData*)data size:(CGSize) size {
    UIImage *image;
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"L" forKey:@"inputCorrectionLevel"];
    UIGraphicsBeginImageContext(size);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGImageRef img = [[CIContext contextWithOptions:nil] createCGImage:filter.outputImage
                                                              fromRect:filter.outputImage.extent];
    
    if (context) {
        CGContextSetInterpolationQuality(context, kCGInterpolationNone);
        CGContextRotateCTM(context, M_PI); // flip
        CGContextScaleCTM(context, -1.0, 1.0); // mirror
        CGContextDrawImage(context, CGContextGetClipBoundingBox(context), img);
        image = UIGraphicsGetImageFromCurrentImageContext();
    }
    UIGraphicsEndImageContext();
    CGImageRelease(img);
    return image;
}

- (UIImage *)negativeImage {
    // get width and height as integers, since we'll be using them as
    // array subscripts, etc, and this'll save a whole lot of casting
    CGSize size = self.size;
    int width = size.width;
    int height = size.height;
    
    // Create a suitable RGB+alpha bitmap context in BGRA colour space
    CGColorSpaceRef colourSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *memoryPool = (unsigned char *)calloc(width*height*4, 1);
    CGContextRef context = CGBitmapContextCreate(memoryPool, width, height, 8, width * 4, colourSpace, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colourSpace);
    
    // draw the current image to the newly created context
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), [self CGImage]);
    
    // run through every pixel, a scan line at a time...
    for(int y = 0; y < height; y++)
    {
        // get a pointer to the start of this scan line
        unsigned char *linePointer = &memoryPool[y * width * 4];
        
        // step through the pixels one by one...
        for(int x = 0; x < width; x++)
        {
            // get RGB values. We're dealing with premultiplied alpha
            // here, so we need to divide by the alpha channel (if it
            // isn't zero, of course) to get uninflected RGB. We
            // multiply by 255 to keep precision while still using
            // integers
            int r, g, b;
            if(linePointer[3])
            {
                r = linePointer[0] * 255 / linePointer[3];
                g = linePointer[1] * 255 / linePointer[3];
                b = linePointer[2] * 255 / linePointer[3];
            }
            else
                r = g = b = 0;
            
            // perform the colour inversion
            r = 255 - r;
            g = 255 - g;
            b = 255 - b;
            
            // multiply by alpha again, divide by 255 to undo the
            // scaling before, store the new values and advance
            // the pointer we're reading pixel data from
            linePointer[0] = r * linePointer[3] / 255;
            linePointer[1] = g * linePointer[3] / 255;
            linePointer[2] = b * linePointer[3] / 255;
            if (r == g && g == b && b == 0){
                linePointer[3] = 0.0;
            }
            linePointer += 4;
        }
    }
    
    // get a CG image from the context, wrap that into a
    // UIImage
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage *returnImage = [UIImage imageWithCGImage:cgImage];
    
    // clean up
    CGImageRelease(cgImage);
    CGContextRelease(context);
    free(memoryPool);
    
    // and return
    return returnImage;
}
@end

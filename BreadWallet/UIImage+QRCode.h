//
//  UIImage+QRCode.h
//  BreadWallet
//
//  Created by Henry on 6/13/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (QRCode)
+ (instancetype)imageWithQRCodeData:(NSData*)data size:(CGSize) size;
@end

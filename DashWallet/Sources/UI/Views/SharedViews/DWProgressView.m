//  
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DWProgressView.h"

#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWProgressView ()

@property (nonatomic, strong) CALayer *greenLayer;
@property (nonatomic, strong) CALayer *blueLayer;

@end

@implementation DWProgressView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor dw_progressBackgroundColor];
    
    CALayer *greenLayer = [CALayer layer];
    greenLayer.backgroundColor = [UIColor dw_greenColor].CGColor;
    [self.layer addSublayer:greenLayer];
    self.greenLayer = greenLayer;
    
    CALayer *blueLayer = [CALayer layer];
    blueLayer.backgroundColor = [UIColor dw_dashBlueColor].CGColor;
    [self.layer addSublayer:blueLayer];
    self.blueLayer = blueLayer;
}

@end

NS_ASSUME_NONNULL_END

//  
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

#import "DWExploreWhereToSpendHandlerView.h"
#import "DWUIKit.h"

@interface DWExploreWhereToSpendHandlerView ()
@property (nonatomic, strong) UIView *handler;
@end

@implementation DWExploreWhereToSpendHandlerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self configureHierarchy];
    }
    return self;
}

- (void)configureHierarchy {

    [self.layer setBackgroundColor:[UIColor dw_backgroundColor].CGColor];
    [self.layer setMasksToBounds:YES];
    [self.layer setCornerRadius:20.0];
    [self.layer setMaskedCorners:kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner];

    self.handler = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 40, 4)];
    _handler.layer.backgroundColor = [UIColor dw_separatorLineColor].CGColor;
    _handler.layer.cornerRadius = 2;
    [self addSubview:_handler];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    self.handler.center = self.center;
}

@end

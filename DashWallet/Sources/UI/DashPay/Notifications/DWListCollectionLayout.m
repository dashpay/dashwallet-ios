//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWListCollectionLayout.h"

@implementation DWListCollectionLayout

- (instancetype)init {
    self = [super init];
    if (self) {
        self.scrollDirection = UICollectionViewScrollDirectionVertical;
        // Using UICollectionViewFlowLayoutAutomaticSize leads to layout issues on reloadData
        self.estimatedItemSize = CGSizeMake(320, 150);
        self.sectionInset = UIEdgeInsetsZero;
        self.minimumInteritemSpacing = 0;
        self.minimumLineSpacing = 0;
        // disabled due to scrolling issues. needs further investigation
        //        self.sectionHeadersPinToVisibleBounds = YES;
    }
    return self;
}

- (CGFloat)contentWidth {
    return ceil(CGRectGetWidth(self.collectionView.safeAreaLayoutGuide.layoutFrame) - self.sectionInset.left - self.sectionInset.right);
}

@end

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

#import "DWStretchyHeaderCollectionViewFlowLayout.h"

@implementation DWStretchyHeaderCollectionViewFlowLayout

- (NSArray<__kindof UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSArray<UICollectionViewLayoutAttributes *> *layoutAttributes = [[super layoutAttributesForElementsInRect:rect] copy];

    for (UICollectionViewLayoutAttributes *attributes in layoutAttributes) {
        if ([attributes.representedElementKind isEqualToString:UICollectionElementKindSectionHeader] &&
            attributes.indexPath.section == 0) {
            UICollectionView *collectionView = self.collectionView;
            const CGFloat contentOffsetY = collectionView.contentOffset.y;
            if (collectionView != nil && contentOffsetY < 0) {
                const CGFloat width = CGRectGetWidth(collectionView.bounds);
                const CGFloat height = CGRectGetHeight(attributes.frame) - contentOffsetY;
                attributes.frame = CGRectMake(0, contentOffsetY, width, height);
            }
        }
    }

    return layoutAttributes;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return YES;
}

@end

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

#import "DWStretchyHeaderListCollectionLayout.h"

@implementation DWStretchyHeaderListCollectionLayout

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

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewLayoutAttributes *superAttributes = [super layoutAttributesForSupplementaryViewOfKind:elementKind atIndexPath:indexPath];
    if ([superAttributes.representedElementKind isEqualToString:UICollectionElementKindSectionHeader] &&
        superAttributes.indexPath.section == 0) {
        UICollectionViewLayoutAttributes *attributes = [superAttributes copy];
        UICollectionView *collectionView = self.collectionView;
        const CGFloat contentOffsetY = collectionView.contentOffset.y;
        if (collectionView != nil && contentOffsetY < 0) {
            const CGFloat width = CGRectGetWidth(collectionView.bounds);
            const CGFloat height = CGRectGetHeight(attributes.frame) - contentOffsetY;
            attributes.frame = CGRectMake(0, contentOffsetY, width, height);
        }
        return attributes;
    }
    else {
        return superAttributes;
    }
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    const CGRect oldBounds = self.collectionView.bounds;
    if (newBounds.origin.y <= 0 || CGRectGetWidth(newBounds) != CGRectGetWidth(oldBounds)) {
        return YES;
    }
    return NO;
}

@end

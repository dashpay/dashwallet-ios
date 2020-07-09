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

static UIEdgeInsets const INSETS = {0.0, 10.0, 0.0, 10.0};

@implementation DWListCollectionLayout

- (instancetype)init {
    self = [super init];
    if (self) {
        self.scrollDirection = UICollectionViewScrollDirectionVertical;
        self.estimatedItemSize = UICollectionViewFlowLayoutAutomaticSize;
        self.sectionInset = INSETS;
        self.sectionHeadersPinToVisibleBounds = YES;
    }
    return self;
}

- (CGFloat)contentWidth {
    return ceil(CGRectGetWidth(self.collectionView.safeAreaLayoutGuide.layoutFrame) - self.sectionInset.left - self.sectionInset.right);
}

- (NSArray<__kindof UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSArray<UICollectionViewLayoutAttributes *> *layoutAttributes = [[super layoutAttributesForElementsInRect:rect] copy];

    for (UICollectionViewLayoutAttributes *attributes in layoutAttributes) {
        if (attributes.representedElementCategory == UICollectionElementCategoryCell) {
            UICollectionViewLayoutAttributes *newAttributes = [self layoutAttributesForItemAtIndexPath:attributes.indexPath];
            if (newAttributes) {
                const CGRect frame = newAttributes.frame;
                attributes.frame = frame;
            }
        }
    }

    return layoutAttributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewLayoutAttributes *attributes = [[super layoutAttributesForItemAtIndexPath:indexPath] copy];
    CGRect frame = attributes.frame;
    frame.origin.x = self.sectionInset.left;
    frame.size.width = self.contentWidth;
    attributes.frame = frame;
    return attributes;
}

@end

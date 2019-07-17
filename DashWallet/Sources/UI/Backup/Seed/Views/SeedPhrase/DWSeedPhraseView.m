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

#import "DWSeedPhraseView.h"

#import "DWSeedPhraseModel.h"
#import "DWSeedPhraseViewLayout.h"
#import "DWSeedWordModel.h"
#import "DWSeedWordView.h"
#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

static UIColor *BackgroundColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return [UIColor dw_backgroundColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_secondaryBackgroundColor];
    }
}

static CGFloat CornerRadius(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return 8.0;
        case DWSeedPhraseType_Select:
            return 0.0;
    }
}

static BOOL MasksToBounds(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return YES;
        case DWSeedPhraseType_Select:
            return NO;
    }
}

#pragma mark - Drag & Drop Helper

@interface DWDragItemLocalObject : NSObject

@property (readonly, nonatomic, strong) DWSeedWordModel *wordModel;
@property (readonly, nullable, nonatomic, weak) id<DWSeedPhraseViewDelegate> externalDelegate;

- (instancetype)init NS_UNAVAILABLE;

@end

@implementation DWDragItemLocalObject

- (instancetype)initWithWord:(DWSeedWordModel *)wordModel delegate:(id<DWSeedPhraseViewDelegate>)delegate {
    self = [super init];
    if (self) {
        _wordModel = wordModel;
        _externalDelegate = delegate;
    }
    return self;
}

@end

#pragma mark - View

@interface DWSeedPhraseView () <DWSeedPhraseViewLayoutDataSource,
                                UIDragInteractionDelegate,
                                UIDropInteractionDelegate>

@property (readonly, nonatomic, assign) DWSeedPhraseType type;

@property (nullable, nonatomic, copy) NSArray<DWSeedWordView *> *wordViews;
@property (nullable, nonatomic, strong) DWSeedPhraseViewLayout *layout;
@property (nonatomic, assign) BOOL hasActiveDragInteractions;

@end

@implementation DWSeedPhraseView

- (instancetype)initWithType:(DWSeedPhraseType)type {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _type = type;

        self.backgroundColor = BackgroundColor(type);

        self.layer.cornerRadius = CornerRadius(type);
        self.layer.masksToBounds = MasksToBounds(type);

        if (type == DWSeedPhraseType_Verify) {
            UIDropInteraction *dropInteraction = [[UIDropInteraction alloc] initWithDelegate:self];
            [self addInteraction:dropInteraction];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)setModel:(nullable DWSeedPhraseModel *)model {
    _model = model;

    self.layout = [[DWSeedPhraseViewLayout alloc] initWithSeedPhrase:model type:self.type];
    self.layout.dataSource = self;

    [self reloadData];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    [self layoutWordViews];
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, self.layout ? self.layout.height : 0.0);
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self reloadData];
}

#pragma mark - DWSeedPhraseViewLayoutDataSource

- (CGFloat)viewWidthForSeedPhraseViewLayout:(DWSeedPhraseViewLayout *)layout {
    return CGRectGetWidth(self.bounds);
}

#pragma mark - Private

- (void)reloadData {
    [self.wordViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.wordViews = nil;

    DWSeedPhraseType type = self.type;

    NSMutableArray<DWSeedWordView *> *wordViews = [NSMutableArray array];
    for (DWSeedWordModel *wordModel in self.model.words) {
        DWSeedWordView *wordView = [[DWSeedWordView alloc] initWithType:type];
        wordView.model = wordModel;
        [self addSubview:wordView];

        if (type == DWSeedPhraseType_Select) {
            [wordView addTarget:self
                          action:@selector(wordViewAction:)
                forControlEvents:UIControlEventTouchUpInside];

            wordView.userInteractionEnabled = YES;
            UIDragInteraction *dragInteraction = [[UIDragInteraction alloc] initWithDelegate:self];
            dragInteraction.enabled = YES;
            [wordView addInteraction:dragInteraction];
        }

        [wordViews addObject:wordView];
    }
    self.wordViews = wordViews;

    [self setNeedsLayout];
}

- (void)layoutWordViews {
    if (self.wordViews.count == 0) {
        return;
    }

    [self.layout performLayout];

    for (DWSeedWordView *wordView in self.wordViews) {
        DWSeedWordModel *wordModel = wordView.model;
        const NSUInteger index = [self.wordViews indexOfObject:wordView];
        const CGRect frame = [self.layout frameForWordAtIndex:index];
        wordView.frame = frame;
    }

    [self invalidateIntrinsicContentSize];
}

#pragma mark - Actions

- (void)wordViewAction:(DWSeedWordView *)sender {
    NSParameterAssert(self.delegate);

    DWSeedWordModel *wordModel = sender.model;
    if (wordModel.isSelected) {
        return;
    }

    BOOL allowed = [self.delegate seedPhraseView:self allowedToSelectWord:wordModel];
    if (allowed) {
        [self.delegate seedPhraseView:self didSelectWord:wordModel];
    }
    else {
        sender.userInteractionEnabled = NO;
        __weak typeof(sender) weakSender = sender;
        [sender animateDiscardedSelectionWithCompletion:^{
            weakSender.userInteractionEnabled = YES;
        }];
    }
}

#pragma mark - UIDragInteractionDelegate

- (NSArray<UIDragItem *> *)dragInteraction:(UIDragInteraction *)interaction
                  itemsForBeginningSession:(id<UIDragSession>)session {
    if (self.hasActiveDragInteractions) {
        // don't allow multiple drags (with multitouch)
        return @[];
    }

    DWSeedWordView *draggingWordView = nil;
    for (DWSeedWordView *wordView in self.wordViews) {
        if (wordView.interactions.firstObject == interaction) {
            draggingWordView = wordView;
            break;
        }
    }

    NSParameterAssert(draggingWordView);
    if (!draggingWordView) {
        return @[];
    }

    DWSeedWordModel *wordModel = draggingWordView.model;
    if (wordModel.selected) {
        // don't allow drag of already selected words
        return @[];
    }

    // Important notice:
    // This drag will be handled in the different instance of DWSeedPhraseView
    // (with type of DWSeedPhraseType_Verify) which adopts UIDropInteractionDelegate.
    // There is no `delegate` set in that view so we provide *ours* delegate along with the word model
    DWDragItemLocalObject *localObject = [[DWDragItemLocalObject alloc] initWithWord:wordModel
                                                                            delegate:self.delegate];

    NSItemProvider *itemProvider = [[NSItemProvider alloc] initWithObject:wordModel.word];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:itemProvider];
    item.localObject = localObject;

    return @[ item ];
}

- (void)dragInteraction:(UIDragInteraction *)interaction sessionWillBegin:(id<UIDragSession>)session {
    // it's safe to assume that drag begins here since after returning an item from
    // `dragInteraction:itemsForBeginningSession:` drag may be cancelled and
    // `dragInteraction:session:didEndWithOperation:` won't be called
    self.hasActiveDragInteractions = YES;
}

- (BOOL)dragInteraction:(UIDragInteraction *)interaction sessionIsRestrictedToDraggingApplication:(id<UIDragSession>)session {
    // in-app drag only
    return YES;
}

- (void)dragInteraction:(UIDragInteraction *)interaction
                session:(id<UIDragSession>)session
    didEndWithOperation:(UIDropOperation)operation {
    self.hasActiveDragInteractions = NO;
}

#pragma mark - UIDropInteractionDelegate

- (BOOL)dropInteraction:(UIDropInteraction *)interaction canHandleSession:(id<UIDropSession>)session {
    if (!session.localDragSession) {
        // don't support drops from other apps
        return NO;
    }

    // skip check of incoming item since we're not properly implementing NSItemProviderWriting for word models
    // `-hasItemsConformingToTypeIdentifiers:`, `-canLoadObjectsOfClass:`, etc.

    // restrict d&d to one by one
    return session.items.count == 1;
}

- (UIDropProposal *)dropInteraction:(UIDropInteraction *)interaction
                   sessionDidUpdate:(id<UIDropSession>)session {
    UIDragItem *dragItem = session.items.firstObject;
    DWDragItemLocalObject *localObject = (DWDragItemLocalObject *)dragItem.localObject;
    DWSeedWordModel *wordModel = (DWSeedWordModel *)localObject.wordModel;
    id<DWSeedPhraseViewDelegate> externalDelegate = localObject.externalDelegate;

    NSAssert([wordModel isKindOfClass:DWSeedWordModel.class], @"Unsupported UIDragItem");
    NSParameterAssert(externalDelegate);

    BOOL valid = [wordModel isKindOfClass:DWSeedWordModel.class] && externalDelegate;
    if (!valid) {
        return [[UIDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }

    BOOL allowed = [externalDelegate seedPhraseView:self allowedToSelectWord:wordModel];
    // UIDropOperationCopy draws (+) icon above the dragging view, UIDropOperationMove - just the animation
    UIDropOperation operation = allowed ? UIDropOperationMove : UIDropOperationForbidden;

    UIDropProposal *dropProposal = [[UIDropProposal alloc] initWithDropOperation:operation];

    return dropProposal;
}

- (void)dropInteraction:(UIDropInteraction *)interaction performDrop:(id<UIDropSession>)session {
    UIDragItem *dragItem = session.items.firstObject;
    DWDragItemLocalObject *localObject = (DWDragItemLocalObject *)dragItem.localObject;
    DWSeedWordModel *wordModel = (DWSeedWordModel *)localObject.wordModel;
    id<DWSeedPhraseViewDelegate> externalDelegate = localObject.externalDelegate;

    NSAssert([wordModel isKindOfClass:DWSeedWordModel.class], @"Unsupported UIDragItem");
    NSParameterAssert(externalDelegate);

    [externalDelegate seedPhraseView:self didSelectWord:wordModel];
}

@end

NS_ASSUME_NONNULL_END

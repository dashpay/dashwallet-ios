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

#import "DWEditProfileViewController.h"

#import <MobileCoreServices/MobileCoreServices.h>

#import "DSBlockchainIdentity+DWDisplayName.h"
#import "DWAvatarEditSelectorViewController.h"
#import "DWCropAvatarViewController.h"
#import "DWEditProfileAvatarView.h"
#import "DWEditProfileTextFieldCell.h"
#import "DWEditProfileTextViewCell.h"
#import "DWEnvironment.h"
#import "DWProfileAboutCellModel.h"
#import "DWProfileDisplayNameCellModel.h"
#import "DWSharedUIConstants.h"
#import "DWTextInputFormTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWEditProfileViewController () <DWEditProfileAvatarViewDelegate, DWEditProfileTextFieldCellDelegate, DWAvatarEditSelectorViewControllerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate, DWCropAvatarViewControllerDelegate>

@property (nullable, nonatomic, strong) DWEditProfileAvatarView *headerView;

@property (nullable, nonatomic, copy) NSArray<DWBaseFormCellModel *> *items;
@property (nullable, nonatomic, strong) DWProfileDisplayNameCellModel *displayNameModel;
@property (nullable, nonatomic, strong) DWProfileAboutCellModel *aboutModel;
@property (nullable, nonatomic, copy) NSString *unsavedAvatarURL;

@end

NS_ASSUME_NONNULL_END

@implementation DWEditProfileViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
    }
    return self;
}

- (NSString *)displayName {
    return self.displayNameModel.text;
}

- (NSString *)aboutMe {
    return self.aboutModel.text;
}

- (NSString *)avatarURLString {
    return self.unsavedAvatarURL ?: self.blockchainIdentity.matchingDashpayUserInViewContext.avatarPath;
}

- (BOOL)isValid {
    return [self.aboutModel postValidate].isErrored == NO && [self.displayNameModel postValidate].isErrored == NO;
}

- (void)updateDisplayName:(NSString *)displayName aboutMe:(NSString *)aboutMe {
    self.displayNameModel.text = displayName;
    self.aboutModel.text = aboutMe;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    self.blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    NSParameterAssert(self.blockchainIdentity);

    [self setupItems];
    [self setupView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    UIView *tableHeaderView = self.tableView.tableHeaderView;
    if (tableHeaderView) {
        CGSize headerSize = [tableHeaderView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        if (CGRectGetHeight(tableHeaderView.frame) != headerSize.height) {
            tableHeaderView.frame = CGRectMake(0.0, 0.0, headerSize.width, headerSize.height);
            self.tableView.tableHeaderView = tableHeaderView;
        }
    }
}

#pragma mark - Private

- (void)setupView {
    self.headerView = [[DWEditProfileAvatarView alloc] initWithFrame:CGRectZero];
    self.headerView.delegate = self;
    [self.headerView setImageWithBlockchainIdentity:self.blockchainIdentity];

    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.tableView.tableHeaderView = self.headerView;

    NSArray<Class> *cellClasses = @[
        DWEditProfileTextViewCell.class,
        DWEditProfileTextFieldCell.class,
    ];
    for (Class cellClass in cellClasses) {
        [self.tableView registerClass:cellClass forCellReuseIdentifier:NSStringFromClass(cellClass)];
    }
}

- (void)setupItems {
    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWProfileDisplayNameCellModel *cellModel = [[DWProfileDisplayNameCellModel alloc] initWithTitle:NSLocalizedString(@"Display Name", nil)];
        self.displayNameModel = cellModel;
        cellModel.autocorrectionType = UITextAutocorrectionTypeNo;
        cellModel.returnKeyType = UIReturnKeyNext;
        cellModel.text = [self.blockchainIdentity dw_displayNameOrUsername];
        __weak typeof(self) weakSelf = self;
        cellModel.didChangeValueBlock = ^(DWTextFieldFormCellModel *_Nonnull cellModel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf.delegate editProfileViewControllerDidUpdate:strongSelf];
        };
        [items addObject:cellModel];
    }

    {
        DWProfileAboutCellModel *cellModel = [[DWProfileAboutCellModel alloc] initWithTitle:NSLocalizedString(@"About me", nil)];
        self.aboutModel = cellModel;
        cellModel.text = self.blockchainIdentity.matchingDashpayUserInViewContext.publicMessage;
        __weak typeof(self) weakSelf = self;
        cellModel.didChangeValueBlock = ^(DWTextFieldFormCellModel *_Nonnull cellModel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf.delegate editProfileViewControllerDidUpdate:strongSelf];
        };
        [items addObject:cellModel];
    }

    self.items = items;
}

#pragma mark - UITableView

- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWBaseFormCellModel *cellModel = self.items[indexPath.row];

    if ([cellModel isKindOfClass:DWTextViewFormCellModel.class]) {
        NSString *cellId = NSStringFromClass(DWEditProfileTextViewCell.class);
        DWEditProfileTextViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                          forIndexPath:indexPath];
        cell.cellModel = (DWTextViewFormCellModel *)cellModel;
        return cell;
    }
    else if ([cellModel isKindOfClass:DWTextFieldFormCellModel.class]) {
        NSString *cellId = NSStringFromClass(DWEditProfileTextFieldCell.class);
        DWEditProfileTextFieldCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                           forIndexPath:indexPath];
        cell.cellModel = (DWTextFieldFormCellModel *)cellModel;
        cell.delegate = self;
        return cell;
    }
    else {
        NSAssert(NO, @"Unknown cell model %@", cellModel);
        return [UITableViewCell new];
    }
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *view = [[UIView alloc] init];
    return view;
}

#pragma mark - DWEditProfileAvatarViewDelegate

- (void)editProfileAvatarView:(DWEditProfileAvatarView *)view editAvatarAction:(UIButton *)sender {
    DWAvatarEditSelectorViewController *controller = [[DWAvatarEditSelectorViewController alloc] init];
    controller.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - DWAvatarEditSelectorViewControllerDelegate

- (void)avatarEditSelectorViewController:(DWAvatarEditSelectorViewController *)controller photoButtonAction:(UIButton *)sender {
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self showImagePickerWithType:UIImagePickerControllerSourceTypeCamera];
                                   }];
}

- (void)avatarEditSelectorViewController:(DWAvatarEditSelectorViewController *)controller galleryButtonAction:(UIButton *)sender {
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self showImagePickerWithType:UIImagePickerControllerSourceTypePhotoLibrary];
                                   }];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES
                               completion:^{
                                   if (image == nil) {
                                       return;
                                   }

                                   DWCropAvatarViewController *cropController = [[DWCropAvatarViewController alloc] initWithImage:image];
                                   cropController.delegate = self;
                                   cropController.modalPresentationStyle = UIModalPresentationFullScreen;
                                   [self presentViewController:cropController animated:YES completion:nil];
                               }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - DWCropAvatarViewControllerDelegate

- (void)cropAvatarViewController:(DWCropAvatarViewController *)controller
                    didCropImage:(UIImage *)croppedImage
                       urlString:(NSString *)urlString {
    self.headerView.image = croppedImage;
    self.unsavedAvatarURL = urlString;

    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)cropAvatarViewControllerDidCancel:(DWCropAvatarViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - DWTextInputFormTableViewCell

- (void)editProfileTextFieldCellActivateNextFirstResponder:(DWEditProfileTextFieldCell *)cell {
    DWTextFieldFormCellModel *cellModel = cell.cellModel;
    NSParameterAssert((cellModel.returnKeyType == UIReturnKeyNext));
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath) {
        return;
    }

    for (NSUInteger i = indexPath.row + 1; i < self.items.count; i++) {
        DWBaseFormCellModel *cellModel = self.items[i];
        if ([cellModel isKindOfClass:DWTextFieldFormCellModel.class]) {
            NSIndexPath *nextIndexPath = [NSIndexPath indexPathForRow:i inSection:0];
            id<DWTextInputFormTableViewCell> cell = [self.tableView cellForRowAtIndexPath:nextIndexPath];
            if ([cell conformsToProtocol:@protocol(DWTextInputFormTableViewCell)]) {
                [cell textInputBecomeFirstResponder];
            }
            else {
                NSAssert(NO, @"Invalid cell class for TextFieldFormCellModel");
            }

            return; // we're done
        }
    }
}

#pragma mark - Private

- (void)showImagePickerWithType:(UIImagePickerControllerSourceType)sourceType {
    if (![UIImagePickerController isSourceTypeAvailable:sourceType]) {
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = sourceType;
    picker.mediaTypes = @[ (id)kUTTypeImage ];
    [self presentViewController:picker animated:YES completion:nil];
}

@end

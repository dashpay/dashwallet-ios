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
#import "DWAvatarGravatarViewController.h"
#import "DWAvatarPublicURLViewController.h"
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
#import "dashwallet-Swift.h"
// if MOCK_DASHPAY
#import "DWDashPayConstants.h"
#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWEditProfileViewController () <DWEditProfileAvatarViewDelegate, DWEditProfileTextFieldCellDelegate, DWAvatarEditSelectorViewControllerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate, DWCropAvatarViewControllerDelegate, DWExternalSourceViewControllerDelegate>

@property (nullable, nonatomic, strong) DWEditProfileAvatarView *headerView;

@property (nullable, nonatomic, copy) NSArray<DWBaseFormCellModel *> *items;
@property (nullable, nonatomic, strong) DWProfileDisplayNameCellModel *displayNameModel;
@property (nullable, nonatomic, strong) DWProfileAboutCellModel *aboutModel;
@property (nullable, nonatomic, copy) NSString *unsavedAvatarURL;
// Row #17 proper: cropped avatar UIImage stashed in `cropAvatarViewController:didCropImage:urlString:`
// so the SDK profile-update path can hand the bytes to `DashPayProfileUpdate.avatarBytes`.
// Stays `readwrite` here, exposed as `readonly` in the header.
@property (nullable, nonatomic, strong, readwrite) UIImage *unsavedAvatarImage;

@end

NS_ASSUME_NONNULL_END

@implementation DWEditProfileViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
    }
    return self;
}

- (BOOL)hasChanges {
    // Row #17 proper: compare against `DWCurrentUserIdentityInfo`
    // (SDK-side profile cache) so the "user has unsaved changes"
    // dialog fires correctly for SDK-only identities. The category
    // method `dw_displayNameOrUsername` on `DSBlockchainIdentity`
    // returns nil for SDK identities (no DashSync row), which made
    // the comparison always-true and incorrectly prompted the save
    // dialog on Cancel.
    DWCurrentUserIdentityInfo *me = DWCurrentUserIdentityInfo.shared;
    NSString *currentTitle = me.displayTitle ?: @"";
    if (![self.displayName isEqualToString:currentTitle]) {
        return YES;
    }

    NSString *currentAbout = me.publicMessage ?: @"";
    NSString *enteredAbout = self.aboutMe ?: @"";
    if (![enteredAbout isEqualToString:currentAbout]) {
        return YES;
    }

    if (self.unsavedAvatarURL != nil) {
        return YES;
    }

    return NO;
}

- (NSString *)displayName {
    return self.displayNameModel.text;
}

- (NSString *)aboutMe {
    return self.aboutModel.text;
}

- (NSString *)avatarURLString {
    // Row #17 proper: fall back to the SDK-sourced avatar URL when
    // the user hasn't picked a new image. Avatars set via DashSync
    // were keyed on `DSBlockchainIdentity.avatarPath` — that read is
    // nil for SDK-only identities.
    return self.unsavedAvatarURL ?: DWCurrentUserIdentityInfo.shared.avatarURL;
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

    // Row #17 proper: the legacy `defaultBlockchainIdentity` read is
    // retained for MOCK_DASHPAY and DashSync-identity backwards
    // compatibility, but for the SDK-only path
    // (`hasIdentity == YES && defaultBlockchainIdentity == nil`) the
    // assertion would fire — so we only assert when MOCK_DASHPAY is
    // on. The SDK path proceeds without a DSBlockchainIdentity; all
    // reads go through `DWCurrentUserIdentityInfo`.
    self.blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;

    if (MOCK_DASHPAY && self.blockchainIdentity == nil) {
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;

        if (username != nil) {
            self.blockchainIdentity = [[DWEnvironment sharedInstance].currentWallet createBlockchainIdentityForUsername:username];
        }
    }

    if (MOCK_DASHPAY) {
        NSParameterAssert(self.blockchainIdentity);
    }

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
    // Row #17 proper: source the avatar from SwiftDashSDK. The
    // legacy `setImageWithBlockchainIdentity:` reads
    // `DSBlockchainIdentity.avatarPath` which is nil for SDK-only
    // identities.
    [self.headerView setImageForCurrentUser];

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
        // Row #17 proper: prefill from SwiftDashSDK profile cache.
        cellModel.text = DWCurrentUserIdentityInfo.shared.displayTitle;
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
        // Row #17 proper: prefill from SwiftDashSDK profile cache.
        cellModel.text = DWCurrentUserIdentityInfo.shared.publicMessage;
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

- (void)avatarEditSelectorViewController:(DWAvatarEditSelectorViewController *)controller gravatarButtonAction:(UIButton *)sender {
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self showGravatarSource];
                                   }];
}

- (void)avatarEditSelectorViewController:(DWAvatarEditSelectorViewController *)controller urlButtonAction:(UIButton *)sender {
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self showPublicURLSource];
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

                                   DWCropAvatarViewController *cropController = [[DWCropAvatarViewController alloc] initWithImage:image imageURL:nil];
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
    // Row #17 proper: retain the cropped UIImage so the SDK
    // profile-update path can hand the bytes to the SDK for hash
    // computation (`DashPayProfileUpdate.avatarBytes`).
    self.unsavedAvatarImage = croppedImage;

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

#pragma mark - DWExternalSourceViewControllerDelegate

- (void)externalSourceViewController:(DWExternalSourceViewController *)controller didLoadImage:(UIImage *)image url:(NSURL *)url shouldCrop:(BOOL)shouldCrop {
    if (!shouldCrop) {
        self.headerView.image = image;
        self.unsavedAvatarURL = url.absoluteString;
        // Row #17 proper: retain the image bytes for SDK hash
        // computation when the source view didn't go through the
        // cropper.
        self.unsavedAvatarImage = image;
        [controller dismissViewControllerAnimated:YES completion:nil];
    }
    else {
        [controller dismissViewControllerAnimated:YES
                                       completion:^{
                                           DWCropAvatarViewController *cropController = [[DWCropAvatarViewController alloc] initWithImage:image imageURL:url];
                                           cropController.delegate = self;
                                           cropController.modalPresentationStyle = UIModalPresentationFullScreen;
                                           [self presentViewController:cropController animated:YES completion:nil];
                                       }];
    }
}

#pragma mark - Private

- (void)showPublicURLSource {
    DWAvatarPublicURLViewController *controller = [[DWAvatarPublicURLViewController alloc] init];
    controller.delegate = self;
    [controller setCurrentInput:[self avatarURLString]];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)showGravatarSource {
    DWAvatarGravatarViewController *controller = [[DWAvatarGravatarViewController alloc] init];
    controller.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

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

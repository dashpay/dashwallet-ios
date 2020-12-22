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

#import "DWCropAvatarViewController.h"

#import <TOCropViewController/TOCropViewController.h>
#import <TOCropViewController/UIImage+CropRotate.h>

#import "DWActionButton.h"
#import "DWBaseActionButtonViewController.h"
#import "DWFaceDetector.h"
#import "DWUIKit.h"
#import "DWUploadAvatarViewController.h"

@interface DWTOCropViewController : TOCropViewController
@end

@implementation DWTOCropViewController

- (CGRect)frameForToolbarWithVerticalLayout:(BOOL)verticalLayout {
    return CGRectZero;
}

- (CGRect)frameForCropViewWithVerticalLayout:(BOOL)verticalLayout {
    return self.view.bounds;
}

@end

NS_ASSUME_NONNULL_BEGIN

static CGFloat const PADDING = 38.0;

@interface DWCropAvatarViewController () <DWUploadAvatarViewControllerDelegate>

@property (nullable, nonatomic, strong) DWFaceDetector *faceDetector;

@property (readonly, nonatomic, strong) TOCropViewController *cropController;
@property (null_resettable, nonatomic, strong) UILabel *titleLabel;
@property (null_resettable, nonatomic, strong) UIButton *selectButton;
@property (null_resettable, nonatomic, strong) UIButton *cancelButton;
@property (null_resettable, nonatomic, strong) UIStackView *buttonsStackView;

@property (nullable, nonatomic, strong) NSURL *imageURL;

@end

NS_ASSUME_NONNULL_END

@implementation DWCropAvatarViewController

- (instancetype)initWithImage:(UIImage *)image imageURL:(NSURL *)imageURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _imageURL = imageURL;

        _cropController = [[DWTOCropViewController alloc] initWithCroppingStyle:TOCropViewCroppingStyleCircular
                                                                          image:image];
        _cropController.hidesNavigationBar = YES;
        _cropController.rotateClockwiseButtonHidden = YES;
        _cropController.rotateButtonsHidden = YES;
        _cropController.resetButtonHidden = YES;
        _cropController.aspectRatioPickerButtonHidden = YES;
        _cropController.doneButtonHidden = YES;
        _cropController.cancelButtonHidden = YES;
        _cropController.cropView.cropViewPadding = PADDING;

        if (image.CGImage) {
            __weak typeof(self) weakSelf = self;
            _faceDetector =
                [[DWFaceDetector alloc] initWithImage:image
                                           completion:^(CGRect roi) {
                                               __strong typeof(weakSelf) strongSelf = weakSelf;
                                               if (!strongSelf) {
                                                   return;
                                               }

                                               if (!CGRectEqualToRect(roi, CGRectZero)) {
                                                   strongSelf.cropController.imageCropFrame = roi;
                                               }

                                               strongSelf.faceDetector = nil;
                                           }];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self dw_embedChild:self.cropController];
    self.cropController.view.preservesSuperviewLayoutMargins = NO;

    [self.view addSubview:self.titleLabel];
    [self.view addSubview:self.buttonsStackView];

    UILayoutGuide *marginsGuide = self.view.layoutMarginsGuide;
    UILayoutGuide *safeAreaGuide = self.view.safeAreaLayoutGuide;

    const CGFloat bottomPadding = [DWBaseActionButtonViewController deviceSpecificBottomPadding];
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:safeAreaGuide.topAnchor
                                                  constant:PADDING * 3],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                      constant:PADDING],
        [self.view.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor
                                                 constant:PADDING],

        [safeAreaGuide.bottomAnchor constraintEqualToAnchor:self.buttonsStackView.bottomAnchor
                                                   constant:bottomPadding],
        [self.buttonsStackView.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [self.buttonsStackView.trailingAnchor constraintEqualToAnchor:marginsGuide.trailingAnchor],
    ]];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (void)selectButtonAction:(UIButton *)sender {
    CGRect cropFrame = self.cropController.cropView.imageCropFrame;
    NSInteger angle = self.cropController.cropView.angle;
    UIImage *croppedImage = [self.cropController.image croppedImageWithFrame:cropFrame angle:angle circularClip:NO];

    // external image
    if (self.imageURL != nil) {
        CGSize imageSize = self.cropController.image.size;

        CGRect rectOfInterest = CGRectMake(cropFrame.origin.x / imageSize.width,
                                           cropFrame.origin.y / imageSize.height,
                                           cropFrame.size.width / imageSize.width,
                                           cropFrame.size.height / imageSize.height);
        // dashpay-profile-pic-zoom=left,top,right,bottom
        NSString *paramSpecifier = nil;
        if ([NSURLComponents componentsWithURL:self.imageURL resolvingAgainstBaseURL:NO].queryItems.count > 0) {
            paramSpecifier = @"&";
        }
        else {
            paramSpecifier = @"?";
        }

        NSString *parameter = [NSString stringWithFormat:@"%@dashpay-profile-pic-zoom=%f,%f,%f,%f",
                                                         paramSpecifier,
                                                         rectOfInterest.origin.x,                               // left,
                                                         rectOfInterest.origin.y,                               // top
                                                         rectOfInterest.origin.x + rectOfInterest.size.width,   // right,
                                                         rectOfInterest.origin.y + rectOfInterest.size.height]; // bottom

        [self.delegate cropAvatarViewController:self
                                   didCropImage:croppedImage
                                      urlString:[self.imageURL.absoluteString stringByAppendingString:parameter]];

        return;
    }

    self.titleLabel.hidden = YES;
    self.buttonsStackView.hidden = YES;

    DWUploadAvatarViewController *controller = [[DWUploadAvatarViewController alloc] initWithImage:croppedImage];
    controller.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)cancelButtonAction:(UIButton *)sender {
    [self.delegate cropAvatarViewControllerDidCancel:self];
}

#pragma mark - DWUploadAvatarViewControllerDelegate

- (void)uploadAvatarViewControllerDidCancel:(DWUploadAvatarViewController *)controller {
    self.titleLabel.hidden = NO;
    self.buttonsStackView.hidden = NO;

    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)uploadAvatarViewController:(DWUploadAvatarViewController *)controller didFinishWithURLString:(NSString *)urlString {
    UIImage *image = controller.image;
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self.delegate cropAvatarViewController:self didCropImage:image urlString:urlString];
                                   }];
}

#pragma mark - Private

- (UILabel *)titleLabel {
    if (_titleLabel == nil) {
        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.numberOfLines = 0;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        label.text = NSLocalizedString(@"Move and Zoom your photo to find the perfect fit", nil);
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.textAlignment = NSTextAlignmentCenter;
        _titleLabel = label;
    }
    return _titleLabel;
}

- (UIButton *)selectButton {
    if (_selectButton == nil) {
        DWActionButton *button = [[DWActionButton alloc] initWithFrame:CGRectZero];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button setTitle:NSLocalizedString(@"Select", nil) forState:UIControlStateNormal];
        [button addTarget:self
                      action:@selector(selectButtonAction:)
            forControlEvents:UIControlEventTouchUpInside];
        _selectButton = button;
    }
    return _selectButton;
}

- (UIButton *)cancelButton {
    if (_cancelButton == nil) {
        DWActionButton *button = [[DWActionButton alloc] initWithFrame:CGRectZero];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.inverted = YES;
        [button setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];
        [button addTarget:self
                      action:@selector(cancelButtonAction:)
            forControlEvents:UIControlEventTouchUpInside];
        _cancelButton = button;
    }
    return _cancelButton;
}

- (UIStackView *)buttonsStackView {
    if (_buttonsStackView == nil) {
        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ self.selectButton, self.cancelButton ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.spacing = 8.0;
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.alignment = UIStackViewAlignmentFill;

        [NSLayoutConstraint activateConstraints:@[
            [self.selectButton.heightAnchor constraintEqualToConstant:DWBottomButtonHeight()],
            [self.cancelButton.heightAnchor constraintEqualToConstant:DWBottomButtonHeight()],
        ]];
        _buttonsStackView = stackView;
    }
    return _buttonsStackView;
}

@end

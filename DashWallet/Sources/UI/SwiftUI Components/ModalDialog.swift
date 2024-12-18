//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

import SwiftUI

struct ModalDialog: View {
    enum Style {
        case regular
        case warning
        case error
    }
    
    var style: Style = .regular
    var icon: IconName? = nil
    var heading: String
    var textBlock1: String? = nil
    var textBlock2: String? = nil
    var smallButtonText: String? = nil
    var smallButtonIcon: IconName? = nil
    var smallButtonAction: (() -> Void)? = nil
    var positiveButtonText: String
    var positiveButtonAction: () -> Void
    var negativeButtonText: String? = nil
    var negativeButtonAction: (() -> Void)? = nil
    var buttonsOrientation: Axis = .vertical
    var buttonsStyle: ButtonsGroup.Style = .regular
    
    var body: some View {
        VStack {
            if let icon = icon {
                switch icon {
                case .custom(let name):
                    Image(name)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                case .system(let name):
                    Image(systemName: name)
                        .resizable()
                        .scaledToFit()
                        .imageScale(.medium)
                        .frame(width: 20, height: 20)
                        .frame(width: 48, height: 48)
                        .foregroundColor(.white)
                        .background(iconBackgroundColor(for: style))
                        .clipShape(Circle())
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                }
            }
            
            Text(heading)
                .font(.subtitle1)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
            
            if let text = textBlock1 {
                Text(text)
                    .font(.body2)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondaryText)
                    .padding(.top, 1)
            }
            
            if let text = textBlock2 {
                Text(text)
                    .font(.body2)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondaryText)
                    .padding(.top, 1)
            }
            
            // TODO: content for limits (crowdnode)
            
            if let text = smallButtonText {
                DashButton(
                    text: text,
                    trailingIcon: smallButtonIcon,
                    style: .plain,
                    size: .extraSmall
                ) {
                    smallButtonAction?()
                }
                .overrideForegroundColor(.dashBlue)
            }
            
            ButtonsGroup(
                orientation: buttonsOrientation,
                style: buttonsStyle,
                positiveButtonText: positiveButtonText,
                positiveButtonAction: positiveButtonAction,
                negativeButtonText: negativeButtonText,
                negativeButtonAction: negativeButtonAction
            )
            .padding(.top, 24)
        }
        .padding(20)
        .background(Color.secondaryBackground)
        .cornerRadius(16)
        .shadow(radius: 10)
        .frame(maxWidth: 340)
    }
    
    private func iconBackgroundColor(for style: Style) -> Color {
        switch style {
        case .regular:
            return .dashBlue
        case .warning:
            return .systemYellow
        case .error:
            return .systemRed
        }
    }
}

extension UIViewController {
    func showModalDialog(
        style: ModalDialog.Style = .regular,
        icon: IconName? = nil,
        heading: String,
        textBlock1: String? = nil,
        textBlock2: String? = nil,
        smallButtonText: String? = nil,
        smallButtonIcon: IconName? = nil,
        smallButtonAction: (() -> Void)? = nil,
        positiveButtonText: String,
        positiveButtonAction: (() -> Void)? = nil,
        negativeButtonText: String? = nil,
        negativeButtonAction: (() -> Void)? = nil,
        buttonsOrientation: Axis = .vertical,
        buttonsStyle: ButtonsGroup.Style = .regular
    ) {
        
        let dialog = ModalDialog(
            style: style,
            icon: icon,
            heading: heading,
            textBlock1: textBlock1,
            textBlock2: textBlock2,
            smallButtonText: smallButtonText,
            smallButtonIcon: smallButtonIcon,
            smallButtonAction: smallButtonAction,
            positiveButtonText: positiveButtonText,
            positiveButtonAction: {
                self.dismiss(animated: true)
                positiveButtonAction?()
            },
            negativeButtonText: negativeButtonText,
            negativeButtonAction: {
                self.dismiss(animated: true)
                negativeButtonAction?()
            },
            buttonsOrientation: buttonsOrientation,
            buttonsStyle: buttonsStyle
        )

        let hostingController = UIHostingController(rootView: dialog)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.modalTransitionStyle = .crossDissolve
        hostingController.view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            
        present(hostingController, animated: true, completion: nil)
    }
}

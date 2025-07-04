//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import MapKit
import SDWebImageSwiftUI

struct POIDetailsView: View {
    @StateObject private var viewModel = POIDetailsViewModel()
    @State private var selectedProvider: GiftCardProvider = .piggyCards
    @State private var usePiggyCards = true
    
    let merchant: ExplorePointOfUse
    let isShowAllHidden: Bool
    
    // Action handlers
    var payWithDashHandler: (() -> Void)?
    var sellDashHandler: (() -> Void)?
    var dashSpendAuthHandler: ((GiftCardProvider) -> Void)?
    var buyGiftCardHandler: ((GiftCardProvider) -> Void)?
    var showAllLocationsActionBlock: (() -> Void)?
    
    init(merchant: ExplorePointOfUse, isShowAllHidden: Bool = false) {
        self.merchant = merchant
        self.isShowAllHidden = isShowAllHidden
    }
    
    var body: some View {
        VStack(spacing: 20) {
            headerView
            
            if case .atm = merchant.category {
                atmButtonsView
                separatorView
            }
            
            locationView
            
            if case .merchant = merchant.category {
                actionButtonsView
            }
            
            Spacer()
            
            if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
                piggyCardsToggle
            }
            
            if case .merchant = merchant.category {
                bottomButtonView
                loginStatusView
            }
        }
        .padding(15)
        .onAppear {
            viewModel.observeDashSpendState(provider: selectedProvider)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 10) {
            // Logo
            Group {
                if let logoUrl = merchant.logoLocation, let url = URL(string: logoUrl) {
                    WebImage(url: url)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(merchant.emptyLogoImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 25))
            
            // Name and subtitle
            VStack(alignment: .leading, spacing: 0) {
                Text(merchant.title ?? "")
                    .font(.headline)
                    .foregroundColor(.primaryText)
                
                if let subtitle = merchant.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondaryText)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Location View
    
    @ViewBuilder
    private var locationView: some View {
        if case .atm = merchant.category {
            atmLocationView
        } else {
            merchantLocationView
        }
    }
    
    private var merchantLocationView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(merchant.address1 ?? "")
                .font(.body)
                .foregroundColor(.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            
            if !isShowAllHidden {
                Button(action: {
                    showAllLocationsActionBlock?()
                }) {
                    Text(NSLocalizedString("View all locations", comment: ""))
                        .foregroundColor(.dashBlue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var atmLocationView: some View {
        HStack(alignment: .top, spacing: 15) {
            // Cover image
            if let coverImage = merchant.coverImage, let url = URL(string: coverImage) {
                WebImage(url: url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 88, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("This ATM is located in the", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondaryText)
                    
                    Text(merchant.name)
                        .font(.headline)
                        .foregroundColor(.primaryText)
                }
                
                Text(merchant.address1 ?? "")
                    .font(.body)
                    .foregroundColor(.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Distance if available
                if let currentLocation = DWLocationManager.shared.currentLocation, 
                   DWLocationManager.shared.isAuthorized,
                   let latitude = merchant.latitude,
                   let longitude = merchant.longitude {
                    HStack(spacing: 5) {
                        Image("image.explore.dash.distance")
                        
                        let distance = CLLocation(latitude: latitude, longitude: longitude)
                            .distance(from: currentLocation)
                        Text(ExploreDash.distanceFormatter.string(from: Measurement(value: floor(distance), unit: UnitLength.meters)))
                            .font(.footnote)
                            .foregroundColor(.secondaryText)
                        
                        Spacer()
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsView: some View {
        HStack(spacing: 8) {
            if let phone = merchant.phone, !phone.isEmpty {
                ActionButtonView(
                    title: NSLocalizedString("Call", comment: ""),
                    icon: .system("phone.circle.fill"),
                    action: callAction
                )
            }
            
            if merchant.showMap {
                ActionButtonView(
                    title: NSLocalizedString("Direction", comment: ""),
                    icon: .system("arrow.triangle.turn.up.right.circle.fill"),
                    action: directionAction
                )
            }
            
            if merchant.website != nil {
                ActionButtonView(
                    title: NSLocalizedString("Website", comment: ""),
                    icon: .system("safari.fill"),
                    action: websiteAction
                )
            }
        }
        .frame(height: 51)
    }
    
    // MARK: - PiggyCards Toggle
    
    private var piggyCardsToggle: some View {
        HStack {
            Toggle("", isOn: $usePiggyCards)
                .labelsHidden()
                .onChange(of: usePiggyCards) { newValue in
                    selectedProvider = newValue ? .piggyCards : .ctx
                    viewModel.observeDashSpendState(provider: selectedProvider)
                }
            
            Text("Open PiggyCards")
                .font(.footnote)
                .foregroundColor(.secondaryText)
            
            Spacer()
        }
    }
    
    // MARK: - Bottom Button
    
    private var bottomButtonView: some View {
        ZStack(alignment: .topTrailing) {
            DashButton(
                text: buttonTitle,
                leadingIcon: buttonIcon,
                style: .filled,
                size: .large,
                isEnabled: isButtonEnabled,
                action: payAction
            )
            .overrideBackgroundColor(buttonTintColor)
            
            // Savings tag
            if case .merchant(let m) = merchant.category, 
               m.paymentMethod == .giftCard,
               m.savingsBasisPoints > 0 {
                SavingsTagSwiftUI(text: String(format: NSLocalizedString("Save %.2f%%", comment: ""), m.toSavingPercentages()))
                    .offset(x: -30, y: -13)
            }
        }
    }
    
    // MARK: - Login Status View
    
    @ViewBuilder
    private var loginStatusView: some View {
        if case .merchant(let m) = merchant.category, 
           m.paymentMethod == .giftCard,
           viewModel.isUserSignedIn {
            HStack {
                Text(emailText)
                    .font(.footnote)
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
                
                Button(action: {
                    viewModel.logout(provider: selectedProvider)
                }) {
                    Text(NSLocalizedString("Log Out", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondaryText)
                        .underline()
                }
            }
            .frame(height: 20)
        }
    }
    
    // MARK: - Computed Properties
    
    private var buttonTitle: String {
        if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
            return NSLocalizedString("Buy a Gift Card", comment: "")
        } else {
            return NSLocalizedString("Pay with Dash", comment: "")
        }
    }
    
    private var buttonIcon: IconName {
        if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
            return .custom("image.explore.dash.gift-card", maxHeight: 20)
        } else {
            return .custom("image.explore.dash.circle", maxHeight: 20)
        }
    }
    
    private var buttonTintColor: Color {
        if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
            return Color(UIColor.dw_orange())
        } else {
            return .dashBlue
        }
    }
    
    private var isButtonEnabled: Bool {
        guard case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard else {
            return true
        }
        
        return merchant.active && 
               viewModel.networkStatus == .online && 
               viewModel.syncState == .syncDone
    }
    
    private var emailText: String {
        if let email = viewModel.userEmail, !email.isEmpty {
            let maskedEmail = maskEmail(email)
            return String.localizedStringWithFormat(NSLocalizedString("Logged in as %@", comment: ""), maskedEmail)
        } else {
            return NSLocalizedString("Logged in", comment: "")
        }
    }
    
    // MARK: - Helper Methods
    
    private func maskEmail(_ email: String) -> String {
        let components = email.components(separatedBy: "@")
        guard components.count == 2 else { return email }
        
        let username = components[0]
        let domain = components[1]
        
        if username.count <= 1 {
            return "******@\(domain)"
        }
        
        let firstChar = String(username.prefix(1))
        return "\(firstChar)******@\(domain)"
    }
    
    // MARK: - Actions
    
    private func callAction() {
        guard let phone = merchant.phone, !phone.isEmpty else { return }
        guard let url = URL(string: "telprompt://\(phone)") else { return }
        UIApplication.shared.open(url)
    }
    
    private func directionAction() {
        guard let longitude = merchant.longitude, let latitude = merchant.latitude else { return }
        
        let coordinate = CLLocationCoordinate2DMake(latitude, longitude)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = merchant.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey : MKLaunchOptionsDirectionsModeDriving])
    }
    
    private func websiteAction() {
        guard let website = merchant.website, let url = URL(string: website) else { return }
        UIApplication.shared.open(url)
    }
    
    private func payAction() {
        if case .merchant(let m) = merchant.category, let deeplink = m.deeplink, let url = URL(string: deeplink),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
            if viewModel.isUserSignedIn {
                buyGiftCardHandler?(selectedProvider)
            } else {
                dashSpendAuthHandler?(selectedProvider)
            }
        } else {
            payWithDashHandler?()
        }
    }
    
    // MARK: - ATM Specific Views
    
    private var atmButtonsView: some View {
        HStack(spacing: 5) {
            DashButton(
                text: NSLocalizedString("Buy Dash", comment: ""),
                style: .filled,
                size: .large,
                action: payAction
            )
            .overrideBackgroundColor(Color(red: 0.235, green: 0.722, blue: 0.471))
            
            if case .atm(let atm) = merchant.category, 
               atm.type == .buySell || atm.type == .sell {
                DashButton(
                    text: NSLocalizedString("Sell Dash", comment: ""),
                    style: .filled,
                    size: .large,
                    action: { sellDashHandler?() }
                )
            }
        }
        .frame(height: 48)
    }
    
    private var separatorView: some View {
        Rectangle()
            .fill(Color.black.opacity(0.3))
            .frame(height: 1/UIScreen.main.scale)
    }
}


// MARK: - Action Button View

private struct ActionButtonView: View {
    let title: String
    let icon: IconName
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Icon(name: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.dashBlue)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.dashBlue)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Savings Tag View

private struct SavingsTagSwiftUI: View {
    let text: String
    
    var body: some View {
        Canvas { context, size in
            let path = Path { path in
                // Main rectangle with tail
                let mainRect = CGRect(x: 8, y: 0, width: size.width - 8, height: size.height)
                path.addRoundedRect(in: mainRect, cornerSize: CGSize(width: 4, height: 4))
                
                // Tail
                path.move(to: CGPoint(x: 8, y: 3))
                path.addLine(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: 8, y: size.height / 2))
                path.closeSubpath()
            }
            
            context.fill(path, with: .color(Color.primaryText.opacity(0.7)))
            
            // Draw text
            let textRect = CGRect(x: 20, y: 0, width: size.width - 32, height: size.height)
            context.draw(Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primaryBackground), 
                in: textRect)
        }
        .frame(height: 26)
        .fixedSize()
    }
}


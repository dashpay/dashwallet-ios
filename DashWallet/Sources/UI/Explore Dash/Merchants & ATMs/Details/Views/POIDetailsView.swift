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
    @StateObject private var viewModel: POIDetailsViewModel
    
    let merchant: ExplorePointOfUse
    let isShowAllHidden: Bool
    let searchRadius: Double?
    
    // Action handlers
    var payWithDashHandler: (() -> Void)?
    var sellDashHandler: (() -> Void)?
    var dashSpendAuthHandler: ((GiftCardProvider) -> Void)?
    var buyGiftCardHandler: ((GiftCardProvider) -> Void)?
    var showAllLocationsActionBlock: (() -> Void)?
    
    init(merchant: ExplorePointOfUse, isShowAllHidden: Bool = false, searchRadius: Double? = nil) {
        self.merchant = merchant
        self.isShowAllHidden = isShowAllHidden
        self.searchRadius = searchRadius

        self._viewModel = StateObject(wrappedValue: POIDetailsViewModel(merchant: merchant, searchRadius: searchRadius))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                headerView
                
                if case .atm = merchant.category {
                    atmButtonsView
                    separatorView
                }
                
                if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
                    if viewModel.showProviderPicker {
                        providerSectionView
                    } else {
                        singleProviderInfoView
                    }
                }
                
                if case .merchant = merchant.category {
                    countryRestrictionView
                    bottomButtonView
                    loginStatusView
                }
            }
            .padding(20)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            
            // Location and contact info card
            if shouldShowLocationView || hasContactInfo {
                VStack(spacing: 2) {
                    if shouldShowLocationView {
                        locationCardView
                    }
                    
                    if let phone = merchant.phone, !phone.isEmpty {
                        phoneCardView
                    }
                    
                    if merchant.website != nil {
                        websiteCardView
                    }
                }
                .padding(10)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .padding(.top, 16)
            }
            
            // Show all locations button
            if !isShowAllHidden && shouldShowLocationView {
                showAllLocationsButton
                    .padding(.top, 16)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 20) {
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
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Name and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(merchant.title ?? "")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primaryText)
                
                if let subtitle = merchant.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondaryText)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Location Views
    
    private var hasContactInfo: Bool {
        (merchant.phone != nil && !merchant.phone!.isEmpty) || merchant.website != nil
    }
    
    private var locationCardView: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Address", comment: "Explore Dash"))
                    .font(.caption)
                    .foregroundColor(.secondaryText)

                if merchant.address1?.isEmpty == false {
                    Text(merchant.address1 ?? "")
                        .font(.body2)
                        .foregroundColor(.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if merchant.address2?.isEmpty == false {
                    Text(merchant.address2 ?? "")
                        .font(.body2)
                        .foregroundColor(.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if merchant.address3?.isEmpty == false {
                    Text(merchant.address3 ?? "")
                        .font(.body2)
                        .foregroundColor(.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Show city and territory (town/state)
                let cityAndTerritory = [merchant.city, merchant.territory].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                if !cityAndTerritory.isEmpty {
                    Text(cityAndTerritory)
                        .font(.body2)
                        .foregroundColor(.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let distanceText = viewModel.distanceText {
                    Text(distanceText)
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }
            }
            
            Spacer()
            
            if merchant.showMap {
                Button(action: directionAction) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.dashBlue)
                }
            }
        }
        .padding(12)
        .padding(.horizontal, 10)
    }
    
    private var phoneCardView: some View {
        Button(action: callAction) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Phone", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                    
                    Text(viewModel.formattedPhoneNumber ?? merchant.phone ?? "")
                        .font(.body2)
                        .foregroundColor(.dashBlue)
                }
                
                Spacer()
            }
            .padding(12)
            .padding(.horizontal, 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var websiteCardView: some View {
        Button(action: websiteAction) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Website", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                            
                    Text(merchant.website ?? "merchant.com")
                        .font(.body2)
                        .foregroundColor(.dashBlue)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Spacer()
            }
            .padding(12)
            .padding(.horizontal, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var showAllLocationsButton: some View {
        Button(action: {
            showAllLocationsActionBlock?()
        }) {
            HStack {
                Text(viewModel.locationCount > 0 ? "\(NSLocalizedString("Show all locations", comment: "Explore Dash")) (\(viewModel.locationCount))" : NSLocalizedString("Show all locations", comment: "Explore Dash"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    
    // MARK: - Provider Section Views
    
    private var providerSectionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("Select gift card provider", comment: "DashSpend"))
                .font(.caption)
                .foregroundColor(.secondaryText)
                .padding(.horizontal, 16)
            
            VStack(spacing: 8) {
                ForEach(Array(viewModel.supportedProviders.keys), id: \.self) { provider in
                    let providerData = viewModel.supportedProviders[provider] ?? (isFixed: false, discount: 0)
                    let isFixedDenom = providerData.isFixed
                    let discount = providerData.discount
                    
                    RadioButtonRow(
                        title: provider.displayName,
                        subtitle: isFixedDenom ? NSLocalizedString("Fixed amounts", comment: "DashSpend") : NSLocalizedString("Flexible amounts", comment: "DashSpend"),
                        trailingText: discount > 0 ? String(format: "-%.0f%%", Double(discount) / 100.0) : nil,
                        isSelected: viewModel.selectedProvider == provider,
                        style: .radio
                    ) {
                        viewModel.selectProvider(provider)
                    }
                    .background(viewModel.selectedProvider == provider ? Color.dashBlue.opacity(0.05) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.selectedProvider == provider ? Color.dashBlue : Color.secondaryText.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(12)
                }
            }
            .padding(6)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
        }
    }
    
    
    private var singleProviderInfoView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedProvider?.displayName ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primaryText)

                if let selectedProvider = viewModel.selectedProvider,
                   let providerData = viewModel.supportedProviders[selectedProvider] {
                    Text(providerData.isFixed ? NSLocalizedString("Fixed amounts", comment: "DashSpend") : NSLocalizedString("Flexible amounts", comment: "DashSpend"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondaryText)
                }
            }

            Spacer()

            if let selectedProvider = viewModel.selectedProvider,
               let providerData = viewModel.supportedProviders[selectedProvider],
               providerData.discount > 0 {
                Text(String(format: "-%.0f%%", Double(providerData.discount) / 100.0))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Country Restriction View

    @ViewBuilder
    private var countryRestrictionView: some View {
        if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
            Text(NSLocalizedString("This card works only in the United States.", comment: "DashSpend"))
                .font(.system(size: 13))
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Bottom Button

    private var bottomButtonView: some View {
        DashButton(
            text: buttonTitle,
            leadingIcon: buttonIcon,
            style: .filled,
            size: .large,
            isEnabled: isButtonEnabled,
            action: payAction
        )
        .overrideBackgroundColor(buttonTintColor)
    }
    
    // MARK: - Login Status View
    
    @ViewBuilder
    private var loginStatusView: some View {
        if case .merchant(let m) = merchant.category, 
           m.paymentMethod == .giftCard,
           viewModel.isUserSignedIn {
            HStack(spacing: 6) {
                Text(providerLoginText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
                
                Button(action: {
                    if let selectedProvider = viewModel.selectedProvider {
                        viewModel.logout(provider: selectedProvider)
                    }
                }) {
                    Text(NSLocalizedString("Log Out", comment: "Log out button"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondaryText)
                        .underline()
                }
            }
            .frame(height: 20)
        }
    }
    
    // MARK: - Computed Properties
    
    private var shouldShowLocationView: Bool {
        // Show location for ATMs
        if case .atm = merchant.category {
            return true
        }
        
        // Show location for physical or online+physical merchants
        if case .merchant(let m) = merchant.category {
            return m.type != .online
        }
        
        return false
    }
    
    private var buttonTitle: String {
        if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
            return NSLocalizedString("Buy a Gift Card", comment: "")
        } else {
            return NSLocalizedString("Pay with Dash", comment: "")
        }
    }
    
    private var buttonIcon: IconName {
        if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
            return .custom("image.explore.dash.wts.card.orange", maxHeight: 20)
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
    
    private var providerLoginText: String {
        let providerName = viewModel.selectedProvider?.displayName ?? ""
        if let email = viewModel.userEmail, !email.isEmpty {
            let maskedEmail = maskEmail(email)
            return "\(providerName): " + String.localizedStringWithFormat(NSLocalizedString("Logged in as %@", comment: ""), maskedEmail)
        } else {
            return "\(providerName): " + NSLocalizedString("Logged in", comment: "")
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
        } else if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard,
                  let selectedProvider = viewModel.selectedProvider {
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

//
//  SendChainStyle.swift
//  DashWallet
//
//  Icons, titles and badges for a chain network or destination kind.
//

import SwiftUI
import DashUIKit
import SwiftDashSDK
import UIKit

// MARK: - Shared helpers

func sourceIconName(_ network: ChainNetwork) -> String {
    switch network {
    case .core: return "d.circle.fill"
    case .platform: return "creditcard.fill"
    case .shielded: return "shield.fill"
    }
}

func sourceTitle(_ network: ChainNetwork) -> String {
    switch network {
    case .core: return NSLocalizedString("Transparent", comment: "Balance breakdown")
    case .platform: return NSLocalizedString("Platform", comment: "Dash Platform chain")
    case .shielded: return NSLocalizedString("Shielded", comment: "")
    }
}

func destinationBadge(_ destination: SendViewModel.DestinationKind) -> some View {
    HStack(spacing: 4) {
        Image(systemName: destinationIconName(destination))
            .font(.system(size: 10, weight: .semibold))
        Text(destinationTitle(destination))
            .font(.caption2.weight(.semibold))
    }
    .foregroundColor(.dashBlue)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Color.dashBlue.opacity(0.1))
    .clipShape(Capsule())
}

func destinationIconName(_ destination: SendViewModel.DestinationKind) -> String {
    switch destination {
    case .core: return "d.circle.fill"
    case .platform: return "creditcard.fill"
    case .shielded: return "shield.fill"
    }
}

func destinationTitle(_ destination: SendViewModel.DestinationKind) -> String {
    switch destination {
    case .core: return NSLocalizedString("Transparent address", comment: "Send screen destination type")
    case .platform: return NSLocalizedString("Platform address", comment: "Send screen destination type")
    case .shielded: return NSLocalizedString("Shielded address", comment: "Send screen destination type")
    }
}

/// Middle-truncated address display shared by the screen's clipboard chip
/// and the confirm sheet's To row.
func truncateMiddle(_ s: String, visible: Int = 8) -> String {
    guard s.count > visible * 2 + 3 else { return s }
    let head = s.prefix(visible)
    let tail = s.suffix(visible)
    return "\(head)…\(tail)"
}

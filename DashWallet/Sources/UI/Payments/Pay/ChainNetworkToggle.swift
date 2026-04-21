//
//  ChainNetworkToggle.swift
//  DashWallet
//

import SwiftUI

enum ChainNetwork: String, CaseIterable, Identifiable {
    case core
    case platform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core: return NSLocalizedString("Core", comment: "Dash Core chain")
        case .platform: return NSLocalizedString("Platform", comment: "Dash Platform chain")
        }
    }
}

struct ChainNetworkToggle: View {
    @Binding var selection: ChainNetwork

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(ChainNetwork.allCases) { network in
                Text(network.title).tag(network)
            }
        }
        .pickerStyle(.segmented)
    }
}

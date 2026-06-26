//
//  MayaCoinIconLoader.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import UIKit

/// Loads remote coin icons with a two-level cache: memory (`NSCache`) + disk (`URLCache`).
///
/// Icons are fetched from the jsupa/crypto-icons repository using the lowercased coin code,
/// matching the Android implementation. Disk-cached entries survive app restarts and are
/// served without re-downloading until the OS purges the cache.
///
/// This actor is responsible only for remote loading and caching.
/// Local asset fallback is handled by `MayaCoinIconView`.
actor MayaCoinIconLoader {
    static let shared = MayaCoinIconLoader()

    private static let swapKitCDNBaseURL = "https://storage.googleapis.com/token-list-swapkit/images/"
    private static let jsupaBaseURL = "https://raw.githubusercontent.com/jsupa/crypto-icons/main/icons/"

    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        let diskCache = URLCache(
            memoryCapacity: 0,
            diskCapacity: 100 * 1024 * 1024,
            diskPath: "maya_coin_icons"
        )
        let config = URLSessionConfiguration.default
        config.urlCache = diskCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)

        memoryCache.countLimit = 200
    }

    /// Primary source: the SwapKit token-list CDN, keyed by the full asset identifier
    /// (e.g. "ARB.USDC-0x…"). Covers ~all SwapKit/Maya tokens.
    func loadSwapKitIcon(for identifier: String) async -> UIImage? {
        guard let url = URL(string: Self.swapKitCDNBaseURL + "\(identifier.lowercased()).png") else {
            return nil
        }
        return await loadIcon(cacheKey: "swapkit:\(identifier.lowercased())", from: url)
    }

    /// Fallback source: the jsupa/crypto-icons repo, keyed by the bare ticker code.
    func loadJsupaIcon(for code: String) async -> UIImage? {
        guard let url = URL(string: Self.jsupaBaseURL + "\(code.lowercased()).png") else {
            return nil
        }
        return await loadIcon(cacheKey: "jsupa:\(code.lowercased())", from: url)
    }

    /// Memory cache is checked first; on miss the image is downloaded and cached.
    private func loadIcon(cacheKey: String, from url: URL) async -> UIImage? {
        let key = cacheKey as NSString

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else {
                return nil
            }
            memoryCache.setObject(image, forKey: key)
            return image
        } catch {
            return nil
        }
    }
}

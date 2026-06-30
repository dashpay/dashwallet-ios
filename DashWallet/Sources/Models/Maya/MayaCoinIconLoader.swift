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
/// The URL is sourced directly from SwapKit's `logoURI` field — no CDN filename construction.
/// Disk-cached entries survive app restarts and are served without re-downloading until the OS
/// purges the cache.
///
/// This actor is responsible only for remote loading and caching.
/// The `convert.crypto` placeholder is shown by `SwapCoinIconView` while loading or on failure.
actor MayaCoinIconLoader {
    static let shared = MayaCoinIconLoader()

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

    /// Tries each candidate URL in order and returns the first image that loads successfully.
    /// Order: `logoURI` (SwapKit) → CoinCap → jsupa. Returns `nil` when all fail.
    func loadIcon(logoURI: String?, ticker: String) async -> UIImage? {
        for url in Self.candidateURLs(logoURI: logoURI, ticker: ticker) {
            if let image = await loadIcon(from: url) { return image }
        }
        return nil
    }

    /// Returns the icon at `url`, or `nil` on any non-200 status, decode failure, or network error.
    /// Memory cache is checked first; on miss the image is downloaded and cached.
    func loadIcon(from url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200, let image = UIImage(data: data) else { return nil }
            memoryCache.setObject(image, forKey: key)
            return image
        } catch {
            return nil
        }
    }

    /// Builds the ordered candidate URL list for a coin icon.
    /// 1. SwapKit `logoURI` (authoritative, chain-qualified)
    /// 2. CoinCap  — `assets.coincap.io/assets/icons/{ticker}@2x.png`
    /// 3. jsupa    — `raw.githubusercontent.com/jsupa/crypto-icons/main/icons/{ticker}.png`
    private static func candidateURLs(logoURI: String?, ticker: String) -> [URL] {
        var urls: [URL] = []
        if let s = logoURI, let u = URL(string: s) { urls.append(u) }
        let t = ticker.lowercased().filter { $0.isLetter || $0.isNumber }
        if !t.isEmpty {
            if let u = URL(string: "https://assets.coincap.io/assets/icons/\(t)@2x.png") { urls.append(u) }
            if let u = URL(string: "https://raw.githubusercontent.com/jsupa/crypto-icons/main/icons/\(t).png") { urls.append(u) }
        }
        return urls
    }
}

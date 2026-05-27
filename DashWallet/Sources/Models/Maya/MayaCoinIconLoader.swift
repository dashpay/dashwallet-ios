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

/// Remote coin icon loader with two-level cache: NSCache (memory) + URLCache (disk).
///
/// Caching strategy:
/// - Memory: NSCache<NSString, UIImage> keyed by lowercased coin code.
///   Auto-evicted under system memory pressure.  Fast O(1) lookup.
/// - Disk: URLCache (100 MB) backing URLSession.  Entries survive app restarts
///   and are served via `.returnCacheDataElseLoad` — no re-download until cache
///   is purged by the OS.
/// - Icons are fetched from https://raw.githubusercontent.com/jsupa/crypto-icons/
///   using the lowercased coin code, matching the Android implementation.
actor MayaCoinIconLoader {

    static let shared = MayaCoinIconLoader()

    private static let baseURL = "https://raw.githubusercontent.com/jsupa/crypto-icons/main/icons/"
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

    /// Loads the icon for a given coin code (lowercased).
    /// Returns nil on network failure or invalid image data.
    func loadIcon(for code: String) async -> UIImage? {
        let key = code.lowercased() as NSString

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        guard let url = URL(string: Self.baseURL + "\(code.lowercased()).png") else {
            return nil
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

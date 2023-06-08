//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - SendReceivePageControllerDelegate

protocol SendReceivePageControllerDelegate: AnyObject {
    func sendReceivePageControllerWillChangeSelectedIndex(to index: Int)
}

// MARK: - SendReceivePageController

class SendReceivePageController: UIPageViewController {
    weak var helperDelegate: SendReceivePageControllerDelegate?

    private var isControllerReady = false

    init() {
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var controllers: [UIViewController]! {
        didSet {
            guard isControllerReady else { return }

            let vc = controllers.first!
            setViewControllers([vc], direction: .forward, animated: false)
        }
    }

    var selectedIndex = 0

    func setSelectedIndex(_ idx: Int, animated: Bool) {
        selectedIndex = idx
        let vc = controllers[selectedIndex]
        let direction = direction(for: vc)
        setViewControllers([vc], direction: direction, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        dataSource = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard selectedIndex < controllers.count else { return }
        let vc = controllers[selectedIndex]
        setViewControllers([vc], direction: .forward, animated: false)

        isControllerReady = true
    }
}

// MARK: UIPageViewControllerDelegate

extension SendReceivePageController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let vc = pendingViewControllers.first else { return }

        let idx = index(of: vc)
        selectedIndex = idx
        helperDelegate?.sendReceivePageControllerWillChangeSelectedIndex(to: idx)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        print("pageViewController", finished, completed, previousViewControllers)
        guard finished else { return }

        if let vc = previousViewControllers.first, !completed {
            let idx = index(of: vc)
            selectedIndex = idx
            helperDelegate?.sendReceivePageControllerWillChangeSelectedIndex(to: idx)
        }
    }
}

// MARK: UIPageViewControllerDataSource

extension SendReceivePageController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        if controllers.last == viewController {
            return controllers.first
        }

        return nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        if controllers.first == viewController {
            return controllers.last
        }

        return nil
    }
}

extension SendReceivePageController {
    // We assume that we can only have two controllers
    func index(of controller: UIViewController) -> Int {
        controllers.first == controller ? 0 : 1
    }

    func direction(for controller: UIViewController) -> UIPageViewController.NavigationDirection {
        let idx = index(of: controller)
        return idx == 0 ? .reverse : .forward
    }
}

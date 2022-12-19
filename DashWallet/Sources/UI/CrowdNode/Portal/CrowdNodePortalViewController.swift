//  
//  Created by Andrei Ashikhmin
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

import Foundation
import Combine

final class CrowdNodePortalController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()
    
    @IBOutlet var gradientHeader: UIView!
    @IBOutlet var contentTable: UITableView!
    @IBOutlet var balanceView: BalanceView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureNavBar()
        configureHierarchy()
        configureObservers()
    }
    
    @objc static func controller() -> CrowdNodePortalController {
        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "CrowdNodePortalController") as! CrowdNodePortalController
        return vc
    }
    
    @objc func infoButtonAction() {
        print("infoButtonAction")
    }
}

extension CrowdNodePortalController {
    private func configureHierarchy() {
        balanceView.tint = .white
        contentTable.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)
        contentTable.clipsToBounds = true
        contentTable.isScrollEnabled = false
        contentTable.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: contentTable.frame.size.width, height: 1))
        
        let colorStart = UIColor(red: 31 / 255.0, green: 134 / 255.0, blue: 201 / 255.0, alpha: 1.0).cgColor
        let colorEnd = UIColor(red: 99 / 255.0, green: 181 / 255.0, blue: 237 / 255.0, alpha: 1.0).cgColor
        let gradientMaskLayer = CAGradientLayer()
        gradientMaskLayer.frame = gradientHeader.bounds
        gradientMaskLayer.colors = [colorStart, colorEnd]
        gradientMaskLayer.locations = [0, 1]
        gradientMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientHeader.layer.insertSublayer(gradientMaskLayer, at: 0)
    }
    
    private func configureNavBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        let image = UIImage(systemName: "chevron.backward")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        appearance.setBackIndicatorImage(image, transitionMaskImage: image)
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        
        let buttonImage = UIImage.init(systemName: "info.circle")
        let button = UIBarButtonItem.init(image: buttonImage, style: UIBarButtonItem.Style.plain, target: self, action: #selector(infoButtonAction))
        button.tintColor = UIColor.white
        navigationItem.rightBarButtonItem = button
    }
    
    private func configureObservers() {
        viewModel.$crowdNodeBalance
            .receive(on: DispatchQueue.main)
            .assign(to: \.balance, on: balanceView)
            .store(in: &cancellableBag)
    }
}

class CrowdNodeCell: UITableViewCell {
    @IBOutlet var title : UILabel!
    @IBOutlet var subtitle : UILabel!
    @IBOutlet var icon : UIImageView!
    @IBOutlet var iconCircle : UIView!
}

extension CrowdNodePortalController : UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.portalItems.count
    }
    
    
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        78
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CrowdNodeCell",
                              for: indexPath) as! CrowdNodeCell
             
        let item = viewModel.portalItems[indexPath.item]
        cell.title.text = item.title
        cell.subtitle.text = item.subtitle
        cell.icon.image = UIImage(named: item.icon)
        cell.iconCircle.backgroundColor = item.iconCircleColor
             
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = viewModel.portalItems[indexPath.item]
        let vc: UIViewController

        switch item {
        default:
            vc = CrowdNodeTransferController.controller()
        }

        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }
}

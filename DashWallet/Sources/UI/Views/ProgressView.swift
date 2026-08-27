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

final class ProgressView: UIView {
    private let kProgressAnimationKey = "DW_PROGRESS_ANIMATION_KEY"
    private let kDelayBetweenPulse: CFTimeInterval = 4.0

    private var greenLayer: CALayer!
    private var blueLayer: CALayer!
    private var animating = false

    var progress: Float = 0.0

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = UIColor.dw_progressBackground()
        layer.masksToBounds = true

        let greenLayer = CALayer()
        greenLayer.backgroundColor = UIColor.dw_green().cgColor
        layer.addSublayer(greenLayer)
        self.greenLayer = greenLayer

        let blueLayer = CALayer()
        blueLayer.backgroundColor = UIColor.dw_dashNavigationBlue().cgColor
        layer.addSublayer(blueLayer)
        self.blueLayer = blueLayer
    }

    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        if layer == self.layer {
            greenLayer.frame = layer.bounds
            blueLayer.frame = layer.bounds
            let x = layer.bounds.width / 2.0
            let y = layer.bounds.height / 2.0
            // set 0 progress position
            greenLayer.position = CGPoint(x: -x, y: y)
            blueLayer.position = CGPoint(x: -x, y: y)
        }
    }

    func setProgress(_ progress: Float, animated: Bool) {
        assert(progress >= 0.0 && progress <= 1.0, "Invalid progress")
        self.progress = max(0.0, min(1.0, progress))

        // use implicit animation
        greenLayer.anchorPoint = CGPoint(x: 0.5 - Double(progress), y: 0.5)

        if progress == 1.0 {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(progressAnimationIteration), object: nil)
            animating = false
        } else if progress > 0.0 && !animating {
            animating = true
            perform(#selector(progressAnimationIteration), with: nil, afterDelay: kDelayBetweenPulse)
        }
    }

    @objc
    private func progressAnimationIteration() {
        if !animating {
            blueLayer.removeAnimation(forKey: kProgressAnimationKey)
            return
        }

        let anchorAnimationDuration: CFTimeInterval = 0.4
        let delayBeforeFadingOut: CFTimeInterval = 0.4
        let colorAnimationDuration: CFTimeInterval = 1.0

        let anchorAnimation = CABasicAnimation(keyPath: "anchorPoint")
        anchorAnimation.fromValue = NSValue(cgPoint: CGPoint(x: 0.5, y: 0.5))
        anchorAnimation.toValue = NSValue(cgPoint: CGPoint(x: 0.5 - Double(progress), y: 0.5))
        anchorAnimation.duration = anchorAnimationDuration
        anchorAnimation.beginTime = 0.0
        anchorAnimation.isRemovedOnCompletion = false
        anchorAnimation.fillMode = .forwards
        anchorAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
        colorAnimation.fromValue = UIColor.dw_dashNavigationBlue().cgColor
        colorAnimation.toValue = UIColor.dw_green().cgColor
        colorAnimation.duration = colorAnimationDuration
        colorAnimation.beginTime = anchorAnimationDuration + delayBeforeFadingOut
        colorAnimation.fillMode = .forwards

        let groupAnimation = CAAnimationGroup()
        groupAnimation.animations = [anchorAnimation, colorAnimation]
        groupAnimation.duration = anchorAnimationDuration +
            delayBeforeFadingOut +
            colorAnimationDuration +
            Double(kDelayBetweenPulse)

        blueLayer.add(groupAnimation, forKey: kProgressAnimationKey)

        perform(#selector(progressAnimationIteration), with: nil, afterDelay: kDelayBetweenPulse)
    }
}


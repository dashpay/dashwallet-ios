//
//  BRAWKeypad.swift
//  DashWallet
//
//  Created by Samuel Sutch on 12/27/15.
//  Copyright (c) 2016 breadwallet LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import WatchKit

protocol BRAWKeypadDelegate: AnyObject {
    func keypadDidFinish(_ stringValueBits: String)
}

final class BRAWKeypadModel {
    weak var delegate: BRAWKeypadDelegate?
    var valueInBits: String = "0"

    init(delegate: BRAWKeypadDelegate?) {
        self.delegate = delegate
    }
}

final class BRAWKeypad: WKInterfaceController {
    var digits: [String] = [String]()
    var ctx: BRAWKeypadModel?

    override func awake(withContext context: Any?) {
        ctx = context as? BRAWKeypadModel
        digits = [String]()
        if let c = ctx {
            for s in c.valueInBits.components(separatedBy: "") {
                digits.append(s)
            }
        }
    }

    override func willDisappear() {
        ctx = nil
    }

    @IBOutlet private var display: WKInterfaceLabel!

    @IBAction private func one(_ sender: AnyObject?) { append("1") }

    @IBAction private func two(_ sender: AnyObject?) { append("2") }

    @IBAction private func three(_ sender: AnyObject?) { append("3") }

    @IBAction private func four(_ sender: AnyObject?) { append("4") }

    @IBAction private func five(_ sender: AnyObject?) { append("5") }

    @IBAction private func six(_ sender: AnyObject?) { append("6") }

    @IBAction private func seven(_ sender: AnyObject?) { append("7") }

    @IBAction private func eight(_ sender: AnyObject?) { append("8") }

    @IBAction private func nine(_ sender: AnyObject?) { append("9") }

    @IBAction private func zero(_ sender: AnyObject?) { append("0") }

    @IBAction private func del(_ sender: AnyObject?) {
        if !digits.isEmpty {
            digits.removeLast()
            fmt()
        }
    }

    @IBAction private func ok(_ sender: AnyObject?) {
        guard let ctx = ctx else { return }
        ctx.delegate?.keypadDidFinish(ctx.valueInBits)
    }

    func append(_ digit: String) {
        digits.append(digit)
        fmt()
    }

    func fmt() {
        var s = "Đ"
        var d = digits
        while !d.isEmpty && d[0] == "0" { d.removeFirst() } // remove remove forward zero padding
        while d.count < 3 { d.insert("0", at: 0) } // add it back correctly
        for i in 0 ... (d.count - 1) {
            if i == d.count - 2 {
                s.append(".")
            }
            s.append(d[i])
        }
        display.setText(s)
        ctx?.valueInBits = s
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "Đ", with: "")
    }
}

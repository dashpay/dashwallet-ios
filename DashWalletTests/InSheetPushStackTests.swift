//
//  InSheetPushStackTests.swift
//  DashWalletTests
//

import SwiftUI
import XCTest
@testable import dashpay

/// `InSheetPushStack` hosted in a window with inert content: a green scrolling root with a black
/// marker 100 points in from its leading edge, and a blue pushed level. The transition is read
/// from frames rendered while it runs, along one row of pixels at the window's mid-height.
@MainActor
final class InSheetPushStackTests: XCTestCase {
    private static let width = 400
    private static let markerInset = 100
    private static let markerWidth = 10

    /// The marker's resting x: its leading inset, from the left or the right edge.
    private static func restingMarker(_ layoutDirection: LayoutDirection) -> Int {
        layoutDirection == .leftToRight ? markerInset : width - markerInset - markerWidth
    }

    /// The root on the left of the window, the pushed level on the right.
    private static let rootLeftPushedRight: ([Frame]) -> Bool = {
        $0.contains { $0.left == .root && $0.right == .pushed }
    }

    private var window: UIWindow?
    private var previousKeyWindow: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
        super.tearDown()
    }

    func testRootKeepsItsScrollPositionAcrossPushAndPop() async throws {
        let route = Route()
        let host = try await show(route)
        let scroll = try XCTUnwrap(findScrollView(in: host.view))
        scroll.setContentOffset(CGPoint(x: 0, y: 500), animated: false)

        route.item = 1
        try await waitFor(.pushed, in: host)
        route.item = nil
        try await waitFor(.root(marker: Self.markerInset), in: host)

        XCTAssertTrue(findScrollView(in: host.view) === scroll)
        XCTAssertEqual(scroll.contentOffset.y, 500, accuracy: 0.5)
    }

    func testPushSlidesInFromTheTrailingEdgeAndShiftsTheRootTowardTheLeading() async throws {
        let route = Route()
        let host = try await show(route)

        let slidesIn = Self.rootLeftPushedRight
        let shiftsRoot: ([Frame]) -> Bool = { $0.contains { ($0.marker ?? .max) < Self.markerInset - 10 } }

        let frames = try await recordPush(host, route, restingMarker: Self.markerInset) {
            slidesIn($0) && shiftsRoot($0)
        }

        XCTAssertTrue(slidesIn(frames), "\(frames)")
        XCTAssertTrue(shiftsRoot(frames), "\(frames)")
        XCTAssertFalse(frames.contains { ($0.marker ?? .min) > Self.markerInset + 1 }, "\(frames)")
    }

    func testPopSlidesOutToTheTrailingEdge() async throws {
        let route = Route()
        let host = try await show(route)
        route.item = 1
        try await waitFor(.pushed, in: host)
        let slidesOut = Self.rootLeftPushedRight

        let frames = try await recordTransition(
            host, from: .pushed, to: .root(marker: Self.markerInset), caught: slidesOut,
            change: { route.item = nil }, undo: { route.item = 1 })

        XCTAssertTrue(slidesOut(frames), "\(frames)")
    }

    func testPushMirrorsInRightToLeftLayouts() async throws {
        let route = Route()
        let host = try await show(route, layoutDirection: .rightToLeft)
        let restingMarker = Self.restingMarker(.rightToLeft)

        let slidesIn: ([Frame]) -> Bool = { $0.contains { $0.left == .pushed && $0.right == .root } }
        let shiftsRoot: ([Frame]) -> Bool = { $0.contains { ($0.marker ?? .min) > restingMarker + 10 } }

        let frames = try await recordPush(host, route, restingMarker: restingMarker) {
            slidesIn($0) && shiftsRoot($0)
        }

        XCTAssertTrue(slidesIn(frames), "\(frames)")
        XCTAssertTrue(shiftsRoot(frames), "\(frames)")
        XCTAssertFalse(frames.contains { ($0.marker ?? .max) < restingMarker - 1 }, "\(frames)")
    }

    func testPushFadesInPlaceUnderReduceMotion() async throws {
        let route = Route()
        let host = try await show(route, reduceMotion: true)

        let fades: ([Frame]) -> Bool = { $0.contains { $0.left == .blend } }

        let frames = try await recordPush(host, route, restingMarker: Self.markerInset, caught: fades)

        XCTAssertFalse(frames.contains { $0.left != $0.right }, "\(frames)")
        XCTAssertTrue(fades(frames), "\(frames)")
        XCTAssertFalse(frames.contains { $0.marker.map { abs($0 - Self.markerInset) > 1 } ?? false }, "\(frames)")
    }

    // MARK: - Host

    private final class Route: ObservableObject {
        @Published var item: Int?
    }

    private struct StackHost: View {
        @ObservedObject var route: Route

        var body: some View {
            InSheetPushStack(pushed: route.item) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<60, id: \.self) { _ in
                            HStack(spacing: 0) {
                                Color(red: 0, green: 1, blue: 0)
                                    .frame(width: CGFloat(InSheetPushStackTests.markerInset))
                                Color.black.frame(width: CGFloat(InSheetPushStackTests.markerWidth))
                                Color(red: 0, green: 1, blue: 0)
                            }
                            .frame(height: 60)
                        }
                    }
                }
            } pushedContent: { _ in
                Color(red: 0, green: 0, blue: 1)
            }
        }
    }

    private func show(
        _ route: Route,
        layoutDirection: LayoutDirection = .leftToRight,
        reduceMotion: Bool = false
    ) async throws -> UIViewController {
        let host = UIHostingController(rootView: StackHost(route: route)
            .environment(\.layoutDirection, layoutDirection)
            .environment(\._accessibilityReduceMotion, reduceMotion))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: Self.width, height: 800)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        // The test host may still be finishing its own launch work on the main thread.
        try await waitFor(.root(marker: Self.restingMarker(layoutDirection)), in: host, timeout: .seconds(15))
        return host
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > view.bounds.height {
            return scroll
        }
        return view.subviews.lazy.compactMap(findScrollView(in:)).first
    }

    // MARK: - Frames

    private enum Paint: String, CustomStringConvertible {
        case root, pushed, blend, marker, other

        var description: String { rawValue }
    }

    private struct Frame: CustomStringConvertible {
        let left: Paint
        let right: Paint
        /// The first x of the root's black marker, when it shows.
        let marker: Int?

        var description: String { "\(left)|\(right)" + (marker.map { "@\($0)" } ?? "") }
    }

    private enum Rest {
        /// The root uncovered, with its marker at the given x.
        case root(marker: Int)
        case pushed

        func matches(_ frame: Frame) -> Bool {
            switch self {
            case .root(let marker):
                frame.left == .root && frame.right == .root && frame.marker.map { abs($0 - marker) <= 1 } == true
            case .pushed:
                frame.left == .pushed && frame.right == .pushed && frame.marker == nil
            }
        }
    }

    private struct NeverSettled: Error, CustomStringConvertible {
        let description: String
    }

    /// Waits until several frames in a row show `rest`; throws when they never do, so the test
    /// stops instead of going on from a moving state.
    private func waitFor(_ rest: Rest, in host: UIViewController, timeout: Duration = .seconds(5)) async throws {
        var streak = 0
        var last: Frame?
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            let frame = frame(of: host.view)
            last = frame
            streak = rest.matches(frame) ? streak + 1 : 0
            if streak == 5 { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NeverSettled(description: "Never settled at \(rest); last frame \(last.map(String.init(describing:)) ?? "none")")
    }

    private func recordPush(
        _ host: UIViewController,
        _ route: Route,
        restingMarker: Int,
        caught: ([Frame]) -> Bool
    ) async throws -> [Frame] {
        try await recordTransition(
            host, from: .root(marker: restingMarker), to: .pushed, caught: caught,
            change: { route.item = 1 }, undo: { route.item = nil })
    }

    /// Frames from `change` until the stack rests at `end`. A run whose own frames do not show
    /// what `caught` looks for, as on a busy machine that stalls through a short transition, is
    /// undone and recorded again; the frames of every run are returned, so a check for what
    /// must never show covers them all.
    private func recordTransition(
        _ host: UIViewController,
        from start: Rest,
        to end: Rest,
        caught: ([Frame]) -> Bool,
        change: () -> Void,
        undo: () -> Void
    ) async throws -> [Frame] {
        var frames: [Frame] = []
        for _ in 0..<3 {
            change()
            var run: [Frame] = []
            let begin = ContinuousClock.now
            while ContinuousClock.now - begin < .seconds(3) {
                let frame = frame(of: host.view)
                run.append(frame)
                if end.matches(frame), run.count > 1 { break }
                try await Task.sleep(for: .milliseconds(8))
            }
            frames += run
            try await waitFor(end, in: host)
            if caught(run) {
                return frames
            }
            undo()
            try await waitFor(start, in: host)
        }
        XCTFail("The transition was not caught in three runs: \(frames)")
        return frames
    }

    /// One row of pixels at the view's mid-height.
    private func frame(of view: UIView) -> Frame {
        let width = Int(view.bounds.width)
        var pixels = [UInt8](repeating: 0, count: width * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: 1, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.translateBy(x: 0, y: 1 + view.bounds.height / 2)
            context.scaleBy(x: 1, y: -1)
            (view.layer.presentation() ?? view.layer).render(in: context)
        }
        func paint(x: Int) -> Paint {
            let red = Int(pixels[x * 4]), green = Int(pixels[x * 4 + 1]), blue = Int(pixels[x * 4 + 2])
            switch (red, green, blue) {
            case (..<56, 200..., ..<56): return .root
            case (..<56, ..<56, 200...): return .pushed
            case (..<24, ..<24, ..<24): return .marker
            case (..<56, 56..<200, 56..<200): return .blend
            default: return .other
            }
        }
        let marker = (0..<width).first { paint(x: $0) == .marker }
        return Frame(left: paint(x: 20), right: paint(x: width - 20), marker: marker)
    }
}

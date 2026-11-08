import SwiftUI
import UIKit

extension View {
    /// 入力欄の外を押すと、キーボードを閉じる。別の入力欄を押したときは、閉じずにその欄へ移る
    func dismissesKeyboardOnTapOutside() -> some View {
        background(KeyboardDismissal())
    }

    /// 押しても、キーボードを閉じない範囲にする。キーボードの上に出すボタンの並びに付ける
    func keepsKeyboardOnTap() -> some View {
        background(KeyboardKeepingArea())
    }
}

private struct KeyboardKeepingArea: UIViewRepresentable {
    func makeUIView(context: Context) -> KeepingView { KeepingView() }
    func updateUIView(_ uiView: KeepingView, context: Context) {}

    final class KeepingView: UIView {}
}

/// 画面の window にタップの認識を足す。SwiftUI のタップでは、ボタンや欄の上を押したときに受け取れないため
private struct KeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(tapped))
            // 押したボタンや行にも、そのままタップを届ける
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()
        private weak var responderAtTouch: UIView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // 入力欄の中を押したときは、欄がカーソルを動かすか、その欄へ移る
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            responderAtTouch = window.flatMap(Self.firstResponder)
            guard let window, let responder = responderAtTouch else { return false }
            let location = touch.location(in: window)
            // キーボードの上のボタンの並びは window の中にあるので、押しても閉じないよう外す
            if Self.keepingAreas(in: window).contains(where: { $0.contains(location) }) { return false }
            // 打っている欄の上下の、押せる範囲を高さ 44pt に広げた余白を押したときも、閉じずにその欄に残る。
            // 余白は欄の外の SwiftUI のビューなので、上の判定では欄の中と分からない
            let frame = responder.convert(responder.bounds, to: window)
            let margin = max(0, (Self.minTapHeight - frame.height) / 2)
            return !frame.insetBy(dx: 0, dy: -margin).contains(location)
        }

        /// 欄の押せる範囲の高さ。RecordView の数字の欄は、この高さまで余白を広げている
        private static let minTapHeight: CGFloat = 44

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func tapped() {
            // 欄のまわりの押せる範囲や「＋ セットを追加」を押すと、同じタップで別の欄へ移る。
            // 移ったかどうかはタップの処理が終わるまで分からないので、次の周回で、入力中の欄が変わっていないときだけ閉じる
            let responder = responderAtTouch
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window, let responder, Self.firstResponder(in: window) === responder else { return }
                window.endEditing(true)
            }
        }

        private static func keepingAreas(in window: UIWindow) -> [CGRect] {
            var areas: [CGRect] = []
            func collect(_ view: UIView) {
                if view is KeyboardKeepingArea.KeepingView {
                    areas.append(view.convert(view.bounds, to: window))
                }
                view.subviews.forEach(collect)
            }
            collect(window)
            return areas
        }

        private static func firstResponder(in view: UIView) -> UIView? {
            if view.isFirstResponder { return view }
            for subview in view.subviews {
                if let responder = firstResponder(in: subview) { return responder }
            }
            return nil
        }
    }
}

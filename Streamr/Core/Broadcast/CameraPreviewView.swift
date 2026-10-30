import SwiftUI
import UIKit

/// Thin UIViewRepresentable wrapping the SDK's camera preview UIView
/// (IVSStageManager.previewView) — the one unavoidable UIKit bridge point
/// for live broadcast, kept as small and isolated as possible.
struct CameraPreviewView: UIViewRepresentable {
    let previewView: UIView?

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewView, previewView.superview !== uiView else { return }
        previewView.removeFromSuperview()
        previewView.translatesAutoresizingMaskIntoConstraints = false
        uiView.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: uiView.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: uiView.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: uiView.trailingAnchor)
        ])
    }
}

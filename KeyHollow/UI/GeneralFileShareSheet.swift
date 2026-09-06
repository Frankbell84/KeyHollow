import Foundation
import SwiftUI
import UIKit

/// App-owned system handoff for authenticated temporary file exports.
/// The caller remains responsible for deleting the temporary files when the
/// system share operation completes.
struct GeneralFileShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: urls,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { onComplete() }
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

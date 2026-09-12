import Foundation
import KeyHollowFileRecognitionAddOn
import KeyHollowTransferCore
import SwiftUI

struct VaultTransferProgressDisplay: Equatable {
    let title: String
    let fractionCompleted: Double?
    let detail: String?

    static func copying(_ progress: VaultFileIngressProgress) -> Self {
        Self(
            title: "Loading encrypted vault…",
            fractionCompleted: progress.fractionCompleted,
            detail: byteDetail(
                completed: progress.completedByteCount,
                total: progress.totalByteCount
            )
        )
    }

    static func validating(_ progress: PortableVaultValidationProgress) -> Self {
        switch progress.phase {
        case .authenticatingArchive:
            return Self(
                title: "Authenticating encrypted archive…",
                fractionCompleted: progress.fractionCompleted,
                detail: byteDetail(
                    completed: progress.completedUnitCount,
                    total: progress.totalUnitCount
                )
            )
        case .authenticatingFiles:
            return Self(
                title: "Verifying files…",
                fractionCompleted: progress.fractionCompleted,
                detail: itemDetail(progress, noun: "file")
            )
        case .authenticatingPhotos:
            return Self(
                title: "Verifying photos…",
                fractionCompleted: progress.fractionCompleted,
                detail: itemDetail(progress, noun: "photo")
            )
        case .finalizing:
            return Self(
                title: "Finishing secure verification…",
                fractionCompleted: nil,
                detail: nil
            )
        }
    }

    private static func byteDetail(completed: UInt64, total: UInt64) -> String {
        let completedText = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: completed),
            countStyle: .file
        )
        let totalText = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: total),
            countStyle: .file
        )
        return "\(completedText) of \(totalText)"
    }

    private static func itemDetail(
        _ progress: PortableVaultValidationProgress,
        noun: String
    ) -> String {
        let pluralized = progress.totalUnitCount == 1 ? noun : "\(noun)s"
        return "\(progress.completedUnitCount) of \(progress.totalUnitCount) \(pluralized)"
    }
}

struct VaultTransferProgressView: View {
    let display: VaultTransferProgressDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(display.title)
                .font(.headline)

            if let fractionCompleted = display.fractionCompleted {
                ProgressView(value: fractionCompleted, total: 1)
                    .progressViewStyle(.linear)
                    .accessibilityValue(Text("\(Int(fractionCompleted * 100)) percent"))
            } else {
                ProgressView()
            }

            if let detail = display.detail {
                Text(detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 300)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

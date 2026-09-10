import Foundation
import SwiftUI

/// A read-only presentation of a completed backup verification. The view owns
/// only the immutable report value and exposes no protected operation.
public struct BackupVerificationReportView: View {
    private let report: BackupVerificationReport
    @AccessibilityFocusState private var statusFocused: Bool

    public init(report: BackupVerificationReport) {
        self.report = report
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                archiveCard
                contentCard

                if case .verifiedWithLegacyLimitations = report.status {
                    legacyCompatibilityCard
                }

                folderCompatibilityCard
                readOnlyCard
            }
            .padding()
        }
        .background(Color.secondary.opacity(0.08))
        .navigationTitle("Backup Verification")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { statusFocused = true }
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            Image(systemName: statusSymbolName)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            Text(BackupVerificationPresentationPolicy.statusTitle(for: report))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(BackupVerificationPresentationPolicy.statusDetail(for: report))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityFocused($statusFocused)
    }

    private var archiveCard: some View {
        reportCard(title: "Backup") {
            reportRow("File", value: report.displayName)
            reportRow(
                "Size",
                value: BackupVerificationPresentationPolicy
                    .formattedArchiveByteCount(report.archiveByteCount)
            )
            reportRow(
                "Payload catalog",
                value: "Version \(report.catalogVersion)"
            )
            reportRow(
                "Vault created",
                value: report.sourceVaultCreatedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
            )
            reportRow(
                "Verified",
                value: report.verifiedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
            )
        }
    }

    private var contentCard: some View {
        reportCard(title: "Authenticated contents") {
            reportRow(
                "Photos",
                value: BackupVerificationPresentationPolicy
                    .photoCountDescription(for: report)
            )
            reportRow(
                "Files",
                value: BackupVerificationPresentationPolicy
                    .generalFileCountDescription(for: report)
            )
            reportRow(
                "Archive entries",
                value: BackupVerificationPresentationPolicy
                    .authenticatedEntryCountDescription(for: report)
            )
            Text("Archive entries include encrypted manifests and thumbnails, so this total can be larger than the photo and file counts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var legacyCompatibilityCard: some View {
        disclosureCard(
            title: "Legacy item limits",
            symbolName: "exclamationmark.triangle.fill",
            tint: .orange,
            text: BackupVerificationPresentationPolicy
                .legacyLimitationDisclosure(for: report) ?? ""
        )
    }

    private var folderCompatibilityCard: some View {
        disclosureCard(
            title: "Folder compatibility",
            symbolName: "folder.badge.questionmark",
            tint: .orange,
            text: BackupVerificationPresentationPolicy.compatibilityDisclosure(
                for: report
            )
        )
    }

    private var readOnlyCard: some View {
        disclosureCard(
            title: "Read-only check",
            symbolName: "lock.shield",
            tint: .blue,
            text: BackupVerificationPresentationPolicy.readOnlyDisclosure
        )
    }

    private var statusSymbolName: String {
        switch report.status {
        case .verified:
            "checkmark.shield.fill"
        case .verifiedWithLegacyLimitations:
            "exclamationmark.shield.fill"
        }
    }

    private var statusColor: Color {
        switch report.status {
        case .verified:
            .green
        case .verifiedWithLegacyLimitations:
            .orange
        }
    }

    private func reportCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func reportRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func disclosureCard(
        title: String,
        symbolName: String,
        tint: Color,
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

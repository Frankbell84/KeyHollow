import SwiftUI
import KeyHollowGalleryUI

/// Receives selection summaries, never record IDs or protected capabilities.
struct VaultGallerySelectionControls: View {
    enum Action {
        case savePhotos, exportFiles, move, delete
    }

    let transferMode: VaultGallerySelection.TransferMode
    let isSelectionEmpty: Bool
    let hasMoveDestination: Bool
    let isWorking: Bool
    let perform: (Action) -> Void

    var body: some View {
        HStack {
            selectionTransferAction

            Spacer()

            selectionMoveAction

            Spacer()

            Button(role: .destructive) {
                perform(.delete)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isSelectionEmpty || isWorking)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var selectionTransferAction: some View {
        switch transferMode {
        case .none:
            EmptyView()
        case .photos:
            Button {
                perform(.savePhotos)
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
            .disabled(isWorking)
        case .generalFiles:
            Button {
                perform(.exportFiles)
            } label: {
                Label("Export Files", systemImage: "square.and.arrow.up")
            }
            .disabled(isWorking)
        case .mixed:
            Menu {
                Button {
                    perform(.savePhotos)
                } label: {
                    Label("Save Photos", systemImage: "square.and.arrow.down")
                }

                Button {
                    perform(.exportFiles)
                } label: {
                    Label("Export Files", systemImage: "square.and.arrow.up")
                }
            } label: {
                Label("Save / Export", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(isWorking)
        }
    }

    private var selectionMoveAction: some View {
        Button {
            perform(.move)
        } label: {
            Label("Move", systemImage: "folder")
        }
        .disabled(isSelectionEmpty || !hasMoveDestination || isWorking)
    }
}

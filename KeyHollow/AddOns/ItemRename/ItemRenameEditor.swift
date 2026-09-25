import SwiftUI

/// Draft ownership and revocation stay with the application's session. No
/// local name copy survives dismissal or a session-driven binding reset.
public struct ItemRenameEditor: View {
    @Binding private var name: String
    private let retainedExtension: String
    private let error: String?
    private let isSaving: Bool
    private let save: () -> Void
    private let cancel: () -> Void

    public init(name: Binding<String>, retainedExtension: String, error: String?,
                isSaving: Bool, save: @escaping () -> Void, cancel: @escaping () -> Void) {
        _name = name
        self.retainedExtension = retainedExtension
        self.error = error
        self.isSaving = isSaving
        self.save = save
        self.cancel = cancel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("itemRenameName")
                        .disabled(isSaving)
                        .onSubmit { if !isSaving { save() } }
                    if !retainedExtension.isEmpty {
                        LabeledContent("File extension", value: retainedExtension)
                    }
                } footer: {
                    Text("Only the name inside this vault changes. Your original stays the same.")
                }
                if let error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("itemRenameError")
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel).disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(isSaving)
                        .accessibilityIdentifier("itemRenameSave")
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }
}

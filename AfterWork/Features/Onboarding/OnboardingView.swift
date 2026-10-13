import SwiftUI

/// Shared form for onboarding and editing; one atomic repository save persists all fields.
struct OnboardingView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    var isEditing = false
    @State private var draft = ProfileDraft()
    @State private var initialized = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, department, jobTitle }
    private let departments = ["Engineering", "Product", "Design", "Marketing", "Finance", "HR", "Operations", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $draft.displayName)
                        .textContentType(.name).textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name).submitLabel(.next)
                        .onSubmit { focusedField = .department }
                    TextField("Department (optional)", text: $draft.department)
                        .textInputAutocapitalization(.words).focused($focusedField, equals: .department)
                        .submitLabel(.next).onSubmit { focusedField = .jobTitle }
                    Menu("Choose a department suggestion") {
                        ForEach(departments, id: \.self) { department in
                            Button(department) { draft.department = department }
                        }
                    }
                    TextField("Job title (optional)", text: $draft.jobTitle)
                        .textContentType(.jobTitle).textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .jobTitle).submitLabel(.done)
                        .onSubmit { focusedField = nil }
                } header: { Text(isEditing ? "About you" : "Welcome to AfterWork") }
                footer: { Text("Your display name is required. You can enter any department.") }

                Section("Interests · optional") {
                    ForEach(ActivityCategory.allCases) { category in
                        Button {
                            if draft.interests.contains(category.databaseSlug) {
                                draft.interests.remove(category.databaseSlug)
                            } else { draft.interests.insert(category.databaseSlug) }
                        } label: {
                            HStack {
                                Label(category.displayName, systemImage: category.symbol)
                                Spacer()
                                if draft.interests.contains(category.databaseSlug) {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                        .accessibilityLabel(category.displayName)
                        .accessibilityValue(draft.interests.contains(category.databaseSlug) ? "Selected" : "Not selected")
                        .accessibilityAddTraits(draft.interests.contains(category.databaseSlug) ? .isSelected : [])
                    }
                }
                Section {
                    if let validation = draft.validationMessage { Text(validation).foregroundStyle(.secondary) }
                    if let message = auth.message { Text(message).foregroundStyle(.red) }
                    Button(isEditing ? "Save Changes" : "Let's Go") {
                        focusedField = nil
                        Task {
                            if await auth.saveProfile(draft), isEditing { dismiss() }
                        }
                    }.disabled(draft.validationMessage != nil || auth.isBusy)
                    if auth.isBusy { ProgressView("Saving…") }
                }
                if !isEditing {
                    Section {
                        Button("Sign Out", role: .destructive) { Task { await auth.signOut() } }
                    }
                }
            }
            .disabled(auth.isBusy)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Profile" : "Your Profile")
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(auth.isBusy) }
                }
            }
            .interactiveDismissDisabled(auth.isBusy)
            .onAppear {
                guard !initialized else { return }
                let name = auth.suggestedName.isEmpty
                    ? auth.metadataName : auth.suggestedName
                draft = ProfileDraft(profile: auth.profile, suggestedName: name)
                initialized = true
            }
        }
    }
}

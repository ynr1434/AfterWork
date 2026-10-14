import SwiftUI

/// Creation and editing use the same form and validation.
struct CreateActivityView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ActivityListViewModel.self) private var activities
    @Environment(\.dismiss) private var dismiss
    @State private var model: ActivityFormViewModel
    @State private var created: Activity?
    @State private var showsSuccess = false
    @FocusState private var focused: Field?
    var isPresentedAsSheet = false
    var onSaved: ((Activity) -> Void)?
    private enum Field: Hashable { case title, description, location, address, capacity }

    init(activity: Activity? = nil, isPresentedAsSheet: Bool = false, onSaved: ((Activity) -> Void)? = nil) {
        _model = State(initialValue: ActivityFormViewModel(activity: activity))
        self.isPresentedAsSheet = isPresentedAsSheet
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Activity") {
                    TextField("Volleyball after work", text: $model.draft.title)
                        .textInputAutocapitalization(.sentences).focused($focused, equals: .title)
                        .submitLabel(.next).onSubmit { focused = .location }
                        .accessibilityLabel("Activity title")
                    Picker("Category", selection: $model.draft.categoryId) {
                        Text("Choose a category").tag(nil as UUID?)
                        ForEach(model.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    if model.isLoadingCategories { ProgressView("Loading categories…") }
                    if model.categories.isEmpty, !model.isLoadingCategories {
                        Button("Retry Categories") { Task { await model.loadCategories() } }
                    }
                    Text("Description · optional").font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $model.draft.description).frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if model.draft.description.isEmpty {
                                Text("What should people know about your plan?")
                                    .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                        .focused($focused, equals: .description).accessibilityLabel("Description, optional")
                }
                Section("When") {
                    DatePicker("Start", selection: $model.draft.startsAt, displayedComponents: [.date, .hourAndMinute])
                    Toggle("Include end date and time", isOn: $model.draft.hasEnd)
                    if model.draft.hasEnd {
                        DatePicker("End", selection: $model.draft.endsAt, displayedComponents: [.date, .hourAndMinute])
                    }
                    Text("Times are shown in your local time zone.").font(AppTypography.caption).foregroundStyle(.secondary)
                }
                Section("Location") {
                    TextField("Office Sports Hall", text: $model.draft.locationName)
                        .focused($focused, equals: .location).submitLabel(.next).onSubmit { focused = .address }
                        .accessibilityLabel("Location name")
                    TextField("Address (optional)", text: $model.draft.locationAddress)
                        .textContentType(.fullStreetAddress).focused($focused, equals: .address)
                        .submitLabel(.done).onSubmit { focused = nil }
                }
                Section("Capacity") {
                    TextField("Maximum participants (optional)", text: $model.draft.maximumParticipants)
                        .keyboardType(.numberPad).focused($focused, equals: .capacity)
                }
                Section("Cover") {
                    Label("Category artwork", systemImage: ActivityCategory(
                        databaseSlug: model.categories.first { $0.id == model.draft.categoryId }?.slug ?? "other"
                    ).symbol)
                    Text("Your activity will use its category artwork.").font(AppTypography.caption).foregroundStyle(.secondary)
                }
                Section {
                    if let validation = model.validationMessage { Text(validation).foregroundStyle(.secondary) }
                    if let error = model.errorMessage { InlineMessage(message: error) }
                    PrimaryButton(title: model.isEditing ? "Save Changes" : "Publish Activity", symbol: model.isEditing ? "checkmark" : "plus", isLoading: model.isSaving) {
                        focused = nil
                        Task {
                            guard let saved = await model.save(userID: auth.userID), auth.userID == saved.authorId else { return }
                            activities.didSave(saved)
                            if model.isEditing { onSaved?(saved); dismiss() }
                            else { created = saved; showsSuccess = true }
                        }
                    }.disabled(!model.canSubmit)

                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .disabled(model.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.isEditing ? "Edit Activity" : "Create Activity")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
                if isPresentedAsSheet || model.isEditing {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isSaving) }
                }
            }
            .interactiveDismissDisabled(model.isSaving)
            .task { await model.loadCategories() }
            .onChange(of: model.needsAuthentication) { _, needed in
                if needed { Task { await auth.restore() } }
            }
            .alert("Activity Published", isPresented: $showsSuccess) {
                Button("View Activity") { /* Dismissing the alert reveals the confirmed activity below. */ }
            } message: { Text("Your activity has been saved and is ready to share.") }
            .navigationDestination(isPresented: Binding(
                get: { created != nil && !showsSuccess },
                set: { showing in
                    if !showing { created = nil; model.resetAfterCreation() }
                }
            )) {
                if let created { ActivityDetailsView(id: created.id) }
            }
        }
    }
}

#Preview { CreateActivityView().environment(AuthManager()).environment(ActivityListViewModel()) }

import SwiftUI
import PhotosUI
import UIKit

/// Creation and editing use the same form and validation.
struct CreateActivityView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ActivityListViewModel.self) private var activities
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var descriptionHeight = 100.0
    @State private var model: ActivityFormViewModel
    @State private var created: Activity?
    @State private var showsSuccess = false
    @State private var coverPickerItem: PhotosPickerItem?
    @FocusState private var focused: Field?
    var isPresentedAsSheet = false
    var onSaved: ((Activity) -> Void)?
    private enum Field: Hashable { case title, description, location, address, capacity }

    init(activity: Activity? = nil,
         initialLocationName: String? = nil,
         initialLocationAddress: String? = nil,
         isPresentedAsSheet: Bool = false,
         onSaved: ((Activity) -> Void)? = nil) {
        _model = State(initialValue: ActivityFormViewModel(
            activity: activity,
            initialLocationName: initialLocationName,
            initialLocationAddress: initialLocationAddress
        ))
        self.isPresentedAsSheet = isPresentedAsSheet
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var model = model
        let coverPickerTitle = model.selectedCoverImageData == nil ? "Choose cover photo" : "Replace cover photo"
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
                    .pickerStyle(.navigationLink)
                    if model.isLoadingCategories { ProgressView("Loading categories…") }
                    if model.categories.isEmpty, !model.isLoadingCategories {
                        Button("Retry Categories") { Task { await model.loadCategories() } }
                    }
                    Text("Description · optional").font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $model.draft.description).frame(minHeight: descriptionHeight)
                        .overlay(alignment: .topLeading) {
                            if model.draft.description.isEmpty {
                                Text("What should people know about your plan?")
                                    .foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.leading, 5)
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
                    coverPreview
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))

                    PhotosPicker(selection: $coverPickerItem, matching: .images) {
                        Label(coverPickerTitle, systemImage: "photo.badge.plus")
                    }
                    .disabled(model.isProcessingCoverImage || model.isSaving)

                    if model.selectedCoverImageData != nil {
                        Button("Remove selected photo", systemImage: "xmark.circle", role: .destructive) {
                            model.setSelectedCoverImage(nil)
                        }
                    }

                    if model.isProcessingCoverImage {
                        ProgressView("Preparing photo…")
                    }
                    if let error = model.coverSelectionErrorMessage {
                        InlineMessage(message: error)
                    }

                    Text(model.selectedCoverImageData == nil
                         ? "Choose a photo for the activity card. If you skip this, the category artwork will be used."
                         : "This photo will appear on the activity card and in its Photos section.")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    if let validation = model.validationMessage { Text(validation).foregroundStyle(.secondary) }
                    if let error = model.errorMessage { InlineMessage(message: error) }
                    PrimaryButton(title: model.isEditing ? "Save Changes" : "Publish Activity", symbol: model.isEditing ? "checkmark" : "plus", isLoading: model.isSaving || model.isProcessingCoverImage) {
                        focused = nil
                        Task {
                            guard let saved = await model.save(userID: auth.userID), auth.userID == saved.authorId else { return }
                            activities.didSave(saved)
                            if model.isEditing { onSaved?(saved); dismiss() }
                            else { created = saved; showsSuccess = true }
                        }
                    }.disabled(!model.canSubmit || model.isProcessingCoverImage)

                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .disabled(model.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.isEditing ? "Edit Activity" : "Create Activity")
            .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? .inline : .large)
            .toolbar {
                if isPresentedAsSheet || model.isEditing {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isSaving) }
                }
            }
            .interactiveDismissDisabled(model.isSaving)
            .task { await model.loadCategories() }
            .onChange(of: coverPickerItem) { _, item in
                guard let item else { return }
                Task {
                    model.setCoverImageProcessing(true)
                    defer {
                        model.setCoverImageProcessing(false)
                        coverPickerItem = nil
                    }
                    do {
                        guard let source = try await item.loadTransferable(type: Data.self) else {
                            throw ActivityPhotoError.invalidImage
                        }
                        let jpeg = try await Task.detached(priority: .userInitiated) {
                            try ActivityPhotoProcessor.process(data: source)
                        }.value
                        try Task.checkCancellation()
                        model.setSelectedCoverImage(jpeg)
                    } catch is CancellationError {
                    } catch {
                        model.setCoverImageSelectionError((error as? ActivityPhotoError)?.localizedDescription ?? ActivityPhotoError.invalidImage.localizedDescription)
                    }
                }
            }
            .onChange(of: model.needsAuthentication) { _, needed in
                if needed { Task { await auth.restore() } }
            }
            .alert("Activity Published", isPresented: $showsSuccess) {
                Button("View Activity") { /* Dismissing the alert reveals the confirmed activity below. */ }
            } message: {
                Text(model.coverUploadErrorMessage ?? "Your activity has been saved and is ready to share.")
            }
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

    @ViewBuilder
    private var coverPreview: some View {
        if let data = model.selectedCoverImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if let coverURL = model.existingCoverImageURL.flatMap(URL.init(string:)) {
            AsyncImage(url: coverURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    categoryCoverPreview
                }
            }
        } else {
            categoryCoverPreview
        }
    }

    private var categoryCoverPreview: some View {
        let category = ActivityCategory(
            databaseSlug: model.categories.first { $0.id == model.draft.categoryId }?.slug ?? "other"
        )
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [category.coverColor.opacity(0.75), category.coverColor.opacity(0.3), AppColors.secondarySurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: category.symbol)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(AppColors.primaryText.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(AppSpacing.lg)
            Text("CATEGORY COVER")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(AppColors.primaryText)
                .padding(AppSpacing.md)
        }
    }
}

#Preview { CreateActivityView().environment(AuthManager()).environment(ActivityListViewModel()) }

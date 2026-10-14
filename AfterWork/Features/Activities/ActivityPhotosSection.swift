import PhotosUI
import SwiftUI

struct ActivityPhotosSection: View {
    let activity: Activity
    @Bindable var model: ActivityPhotosViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedIndex: Int?
    @State private var pendingDelete: ActivityPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.sm)) : AnyLayout(HStackLayout())) {
                Text("Photos").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Text("· \(model.photos.count)/\(ActivityPhotoRules.maximumPhotoCount)").foregroundStyle(.secondary)
                Spacer()
                if model.canUpload && model.photos.count < ActivityPhotoRules.maximumPhotoCount {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("Add Photo", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isUploading)
                }
            }
            if model.isUploading { ProgressView("Preparing and uploading photo…") }
            if model.isLoading && model.photos.isEmpty { ProgressView() }
            else if model.photos.isEmpty && model.errorMessage == nil {
                Text(model.canUpload ? "Share a moment from this activity. Add the first photo." : "Photos shared by attendees will appear here.").font(.subheadline).foregroundStyle(.secondary)
            }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: AppSpacing.sm) {
                        ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                            VStack(spacing: AppSpacing.xs) {
                            Button { selectedIndex = index } label: {
                                photoThumbnail(photo)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Photo \(index + 1) of \(model.photos.count)")
                            .accessibilityHint("Open full screen")
                            Menu {
                                if model.canDelete(photo) {
                                    Button("Delete Photo", systemImage: "trash", role: .destructive) {
                                        pendingDelete = photo
                                    }
                                }
                            } label: {
                                if model.canDelete(photo) {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                }
                            }.accessibilityLabel("Photo actions").disabled(model.deletingPhotoID != nil)
                            if model.deletingPhotoID == photo.id { ProgressView("Deleting…").font(.caption) }
                            }
                        }
                    }
                }
            }
            if let error = model.errorMessage {
                InlineMessage(message: error) { Task { await model.load(activity: activity, currentUserID: model.currentUserID) } }
                    .disabled(model.isLoading || model.isUploading || model.deletingPhotoID != nil)
            }
        }
        .padding(.top, AppSpacing.sm)
        .onChange(of: selectedItem) { _, item in
            guard item != nil else { return }
            Task { await model.upload(item, activity: activity); selectedItem = nil }
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedIndex != nil },
            set: { if !$0 { selectedIndex = nil } }
        )) {
            if let selectedIndex {
                ActivityPhotoGalleryView(photos: model.photos, initialIndex: selectedIndex)
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) {
                guard let photo = pendingDelete else { return }
                pendingDelete = nil
                Task { await model.delete(photo) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { Text("This photo will be removed from the activity.") }
    }

    @ViewBuilder
    private func photoThumbnail(_ photo: ActivityPhoto) -> some View {
        Group {
            if let url = photo.displayURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else if phase.error != nil { imagePlaceholder }
                    else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
            } else { imagePlaceholder }
        }
        .frame(width: 116, height: 116)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
    }

    private var imagePlaceholder: some View {
        Label("Unavailable", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ActivityPhotoGalleryView: View {
    let photos: [ActivityPhoto]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(photos: [ActivityPhoto], initialIndex: Int) {
        self.photos = photos
        _index = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                    Group {
                        if abs(offset - index) > 1 { Color.clear }
                        else if let url = photo.displayURL {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFit() }
                                else if phase.error != nil { ContentUnavailableView("Photo unavailable", systemImage: "photo") }
                                else { ProgressView().tint(.white) }
                            }
                        } else { ContentUnavailableView("Photo unavailable", systemImage: "photo") }
                    }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).font(.headline).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                    .accessibilityLabel("Close photos")
                Spacer()
                Text("\(index + 1) of \(photos.count)").font(.subheadline).foregroundStyle(.white)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Previous", systemImage: "chevron.left") { index -= 1 }.disabled(index == 0)
                Spacer()
                Button("Next", systemImage: "chevron.right") { index += 1 }.disabled(index >= photos.count - 1)
            }.buttonStyle(.bordered).padding().foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}

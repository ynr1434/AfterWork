import PhotosUI
import SwiftUI

struct ActivityPhotosSection: View {
    let activity: Activity
    @Bindable var model: ActivityPhotosViewModel
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedIndex: Int?
    @State private var pendingDelete: ActivityPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Photos").font(AppTypography.headline)
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
            if model.isUploading { ProgressView("Preparing photo…") }
            if model.isLoading && model.photos.isEmpty { ProgressView() }
            else if model.photos.isEmpty { Text("No photos yet.").foregroundStyle(.secondary) }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                            Button { selectedIndex = index } label: {
                                photoThumbnail(photo)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if model.canDelete(photo) {
                                    Button("Delete Photo", systemImage: "trash", role: .destructive) {
                                        pendingDelete = photo
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
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
        Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
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
                        if let url = photo.displayURL {
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
                Spacer()
                Text("\(index + 1) of \(photos.count)").font(.subheadline).foregroundStyle(.white)
            }
            .padding()
        }
        .statusBarHidden()
    }
}

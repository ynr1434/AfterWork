import SwiftUI

struct FeedView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isShowingSavedPlaces = false
    @AppStorage("feed.savedPlaceIDs") private var savedPlaceIDsData = Data()

    private var suggestions: [AlmatyPlaceSuggestion] { AlmatyPlaceSuggestions.all }
    private var currentSuggestion: AlmatyPlaceSuggestion? {
        suggestions.indices.contains(index) ? suggestions[index] : nil
    }
    private var savedPlaceIDs: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: savedPlaceIDsData)) ?? [])
    }
    private var savedSuggestions: [AlmatyPlaceSuggestion] {
        suggestions.filter { savedPlaceIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.md) {
                header

                if let suggestion = currentSuggestion {
                    PlaceSuggestionCard(suggestion: suggestion)
                        .frame(maxWidth: 560, maxHeight: .infinity)
                        .frame(maxWidth: .infinity)
                        .offset(dragOffset)
                        .rotationEffect(.degrees(Double(dragOffset.width / 22)))
                        .overlay(alignment: .topLeading) { swipeStamp("NOPE", color: .red, visible: dragOffset.width < -24) }
                        .overlay(alignment: .topTrailing) { swipeStamp("SAVED", color: .green, visible: dragOffset.width > 24) }
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    guard abs(value.translation.width) > abs(value.translation.height),
                                          abs(value.translation.width) > 90 else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = .zero }
                                        return
                                    }
                                    finishSwipe(direction: value.translation.width > 0 ? 1 : -1)
                                }
                        )
                        .accessibilityAction(named: "Save place") { finishSwipe(direction: 1) }
                        .accessibilityAction(named: "Pass on place") { finishSwipe(direction: -1) }
                        .id(suggestion.id)
                        .transition(reduceMotion ? .identity : .opacity)
                } else {
                    finishedState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
            .background(AppColors.appBackground)
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingSavedPlaces) {
                SavedPlacesView(suggestions: savedSuggestions) { suggestion in
                    removeSaved(suggestion)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("ALMATY · AFTER WORK")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.accent)
                Text("Where should we go?")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button { isShowingSavedPlaces = true } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 48, height: 48)
                    .background(AppColors.secondarySurface, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if !savedPlaceIDs.isEmpty {
                            Text("\(savedPlaceIDs.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(AppColors.accent, in: Circle())
                                .offset(x: 3, y: -3)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Saved places, \(savedPlaceIDs.count)")
        }
    }

    private var finishedState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.accent)
            Text("You’re all caught up")
                .font(.title3.bold())
            Text("Your saved places are waiting in the bookmark above.")
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
            Button("Start over") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { index = 0 }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
        }
        .padding(AppSpacing.xl)
    }

    private func swipeStamp(_ title: String, color: Color, visible: Bool) -> some View {
        Text(title)
            .font(.title2.weight(.black))
            .tracking(1.5)
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
            .padding(AppSpacing.lg)
            .opacity(visible ? 1 : 0)
            .rotationEffect(.degrees(title == "NOPE" ? -12 : 12))
            .accessibilityHidden(true)
    }

    private func finishSwipe(direction: CGFloat) {
        guard currentSuggestion != nil else { return }
        let suggestion = suggestions[index]
        let width = UIScreen.main.bounds.width * (direction > 0 ? 1.25 : -1.25)
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) {
            dragOffset = CGSize(width: width, height: 30)
        }
        if direction > 0 { save(suggestion) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.2)) {
            dragOffset = .zero
            index += 1
        }
    }

    private func save(_ suggestion: AlmatyPlaceSuggestion) {
        var ids = savedPlaceIDs
        ids.insert(suggestion.id)
        savedPlaceIDsData = (try? JSONEncoder().encode(ids.sorted())) ?? Data()
    }

    private func removeSaved(_ suggestion: AlmatyPlaceSuggestion) {
        var ids = savedPlaceIDs
        ids.remove(suggestion.id)
        savedPlaceIDsData = (try? JSONEncoder().encode(ids.sorted())) ?? Data()
    }
}

private struct SavedPlacesView: View {
    let suggestions: [AlmatyPlaceSuggestion]
    let onRemove: (AlmatyPlaceSuggestion) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if suggestions.isEmpty {
                    ContentUnavailableView("No saved places", systemImage: "bookmark", description: Text("Swipe right on a place to save it here."))
                } else {
                    List(suggestions) { suggestion in
                        NavigationLink {
                            PlaceSuggestionDetailsView(suggestion: suggestion)
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: suggestion.symbol)
                                    .font(.title3)
                                    .foregroundStyle(suggestion.tint)
                                    .frame(width: 42, height: 42)
                                    .background(suggestion.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    Text(suggestion.name).font(.headline)
                                    Text("\(suggestion.category) · \(suggestion.area)")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .padding(.vertical, AppSpacing.xs)
                        .swipeActions {
                            Button("Remove", systemImage: "bookmark.slash", role: .destructive) {
                                onRemove(suggestion)
                            }
                            .tint(.red)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved places")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PlaceSuggestionDetailsView: View {
    let suggestion: AlmatyPlaceSuggestion
    @State private var isShowingCreateActivity = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
            PlacePhotoHero(suggestion: suggestion, height: 230)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Label("\(suggestion.category) · \(suggestion.area)", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryText)
                    Text(suggestion.name)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(suggestion.pitch)
                        .font(.title3)
                        .foregroundStyle(AppColors.secondaryText)
                    Text(suggestion.details)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(suggestion.groupIdea, systemImage: "person.3.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(suggestion.tint)
                        .padding(AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(suggestion.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                    Text("Place suggestions are for planning. Confirm current venue details before you go.")
                        .font(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }

                PrimaryButton(title: "Create activity here", symbol: "plus") {
                    isShowingCreateActivity = true
                }
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.appBackground)
        .navigationTitle(suggestion.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingCreateActivity) {
            CreateActivityView(
                initialLocationName: suggestion.name,
                initialLocationAddress: suggestion.area,
                isPresentedAsSheet: true
            )
        }
    }
}

private struct PlaceSuggestionCard: View {
    let suggestion: AlmatyPlaceSuggestion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .frame(maxHeight: .infinity)
                .layoutPriority(1)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Label(suggestion.category, systemImage: "sparkle")
                    Spacer(minLength: AppSpacing.xs)
                    Label(suggestion.area, systemImage: "mappin.and.ellipse")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)

                Text(suggestion.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(suggestion.pitch)
                    .font(.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(AppColors.separator).frame(height: 1)

                Label {
                    Text(suggestion.groupIdea)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(suggestion.tint)
                }
            }
            .padding(AppSpacing.md)
        }
        .foregroundStyle(AppColors.primaryText)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
        .surfaceCard(radius: AppCornerRadius.large)
        .accessibilityElement(children: .contain)
    }

    private var hero: some View {
        PlacePhotoHero(suggestion: suggestion, height: nil)
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
    }
}

private struct PlacePhotoHero: View {
    let suggestion: AlmatyPlaceSuggestion
    var height: CGFloat? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Image(suggestion.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.08), .black.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .top) {
                    Text("ALMATY PLACE")
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(.black.opacity(0.28), in: Capsule())
                    Spacer()
                    Image(systemName: suggestion.symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.25), in: Circle())
                }
                .padding(AppSpacing.lg)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#Preview {
    FeedView()
}

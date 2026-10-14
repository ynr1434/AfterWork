import SwiftUI

struct ActivityCommentsSection: View {
    let activityID: UUID
    @Bindable var model: CommentsViewModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Discussion").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Text("\(model.comments.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if model.isLoading && model.comments.isEmpty { ProgressView("Loading discussion…") }
            else if model.comments.isEmpty && model.errorMessage == nil {
                Label("Start the conversation. Ask a question or say hello.", systemImage: "text.bubble")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, AppSpacing.sm)
            }
            ForEach(model.comments) { comment in commentRow(comment) }
            if let error = model.errorMessage {
                InlineMessage(message: error) { Task { await model.load(activityID: activityID) } }
                    .disabled(model.isSending || model.isLoading)
            }
            if !model.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.suggestions) { suggestion in
                        Button { model.selectSuggestion(suggestion) } label: {
                            HStack {
                                AvatarView(initials: suggestion.initials, size: 28).accessibilityHidden(true)
                                Text("@\(suggestion.name)")
                                Spacer()
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityHint("Mention this coworker")
                    }
                }.padding(AppSpacing.sm).surfaceCard()
            }
            if model.editingComment != nil {
                HStack {
                    Label("Editing comment", systemImage: "pencil").font(.subheadline)
                    Spacer()
                    Button("Cancel") { model.cancelEditing() }.disabled(model.isSending).frame(minHeight: 44)
                }
            }
            HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                TextField("Add a comment… Use @ to mention", text: $model.draft, axis: .vertical)
                    .lineLimit(2...6).padding(AppSpacing.sm).surfaceCard()
                    .focused($composerFocused).disabled(model.isSending)
                    .accessibilityLabel(model.editingComment == nil ? "Comment" : "Edit comment")
                    .onChange(of: model.draft) { _, _ in model.updateSuggestions() }
                Button {
                    Task { await model.submit(activityID: activityID); if model.draft.isEmpty { composerFocused = false } }
                } label: {
                    Group {
                        if model.isSending { ProgressView().tint(.white) }
                        else { Image(systemName: model.editingComment == nil ? "arrow.up" : "checkmark").font(.headline) }
                    }.frame(width: 28, height: 32)
                }
                .buttonStyle(.borderedProminent).tint(AppColors.buttonFill).foregroundStyle(.white).disabled(!model.canSubmit)
                .accessibilityLabel(model.editingComment == nil ? "Send comment" : "Save comment")
                .accessibilityValue(model.isSending ? "Sending" : "")
            }
            if model.draft.count > CommentRules.maximumLength - 200 {
                Text("\(model.draft.count) / \(CommentRules.maximumLength) characters")
                    .font(.caption).foregroundStyle(model.draft.count > CommentRules.maximumLength ? AppColors.error : .secondary)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { composerFocused = false }
            }
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            if !typeSize.isAccessibilitySize { AvatarView(initials: comment.authorInitials, size: 34).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(comment.authorName).font(.subheadline.weight(.semibold))
                        Text(comment.createdAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if comment.authorId == auth.userID {
                        Menu {
                            Button("Edit", systemImage: "pencil") { model.beginEditing(comment); composerFocused = true }
                            Button("Delete", systemImage: "trash", role: .destructive) { model.pendingDelete = comment }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .disabled(model.isSending).accessibilityLabel("Actions for your comment")
                    }
                }
                Text(mentionText(comment.body)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if comment.isEdited { Text("Edited").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(AppSpacing.md).frame(maxWidth: .infinity, alignment: .leading).surfaceCard()
        }
    }

    private func mentionText(_ body: String) -> AttributedString {
        var result = AttributedString(body)
        for token in body.split(whereSeparator: { $0.isWhitespace }) where token.first == "@" {
            if let range = result.range(of: String(token)) {
                result[range].foregroundColor = AppColors.accent
                result[range].font = .body.bold()
            }
        }
        return result
    }
}

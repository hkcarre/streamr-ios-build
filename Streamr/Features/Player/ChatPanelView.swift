import SwiftUI

/// Live chat panel, shared by the viewer (PlayerView) and the host
/// (AddStreamStagingView). Presented as a sheet rather than a side column —
/// the website puts chat beside the video (`.live-chat-wrap`), which has no
/// sensible phone equivalent at 390pt wide.
struct ChatPanelView: View {
    @ObservedObject var chat: IVSChatManager
    /// Why chat couldn't be set up at all — distinct from a connect that was
    /// attempted and failed (`chat.state == .failed`). Without this the panel
    /// opened completely blank when `/stream/chat-room` returned no room: no
    /// status, no messages, and a composer whose send button was silently
    /// disabled, with nothing on screen explaining any of it.
    var unavailableReason: String?
    /// Re-runs the setup. Nil when the caller has nothing to retry.
    var onRetry: (() -> Void)?

    @EnvironmentObject private var moderation: ModerationStore

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool
    /// The message the person is reporting, if any. Drives the sheet.
    @State private var reporting: ReportSubject?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.15))
            if let unavailableReason {
                unavailableBanner(unavailableReason)
            }
            messageList
            composer
        }
        .streamrBackground()
        .sheet(item: $reporting) { subject in
            ReportSheet(subject: subject)
        }
    }

    private func unavailableBanner(_ reason: String) -> some View {
        VStack(spacing: 10) {
            Text(reason)
                .font(StreamrFont.caption())
                .foregroundStyle(StreamrColor.warningGold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let onRetry {
                Button("Try Again", action: onRetry)
                    .font(StreamrFont.headline(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    private var header: some View {
        HStack {
            Text("Live Chat")
                .font(StreamrFont.headline(17))
                .foregroundStyle(.white)
            Spacer()
            statusDot
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var statusDot: some View {
        switch chat.state {
        case .connected:
            Label("Connected", systemImage: "circle.fill")
                .font(StreamrFont.caption(11))
                .foregroundStyle(StreamrColor.successGreen)
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6).tint(.white)
                Text("Connecting…").font(StreamrFont.caption(11))
            }
            .foregroundStyle(.white.opacity(0.7))
        case .failed:
            Label("Offline", systemImage: "exclamationmark.triangle.fill")
                .font(StreamrFont.caption(11))
                .foregroundStyle(StreamrColor.warningGold)
        case .idle:
            EmptyView()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if case .failed(let reason) = chat.state {
                        Text(reason)
                            .font(StreamrFont.caption())
                            .foregroundStyle(StreamrColor.warningGold)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if visibleMessages.isEmpty, chat.state == .connected {
                        Text("No messages yet — say hello.")
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 20)
                    }

                    ForEach(visibleMessages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            // Auto-scroll to the newest message, matching the web app's
            // scrollTop-on-new-message behaviour.
            .onChange(of: chat.messages.count) { _, _ in
                guard let last = chat.messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// Messages from people this device has blocked are dropped here rather
    /// than inside IVSChatManager: the manager's job is the room, and a block
    /// is a per-viewer display choice that shouldn't make the transcript it
    /// holds depend on who is looking at it.
    private var visibleMessages: [IVSChatManager.Message] {
        chat.messages.filter {
            !moderation.isBlockedSender(userId: $0.userId, userName: $0.userName)
        }
    }

    private func messageRow(_ message: IVSChatManager.Message) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(for: message)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.userName)
                    .font(StreamrFont.caption(11))
                    .foregroundStyle(.white.opacity(0.6))
                Text(message.content)
                    .font(StreamrFont.body())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        // Long-press rather than a visible button on every row: a per-message
        // control would crowd a 390pt-wide panel, and this is the gesture iOS
        // users already expect for message actions. Nothing is offered on your
        // own messages -- reporting yourself is noise.
        .contextMenu {
            if !message.isMine {
                Button {
                    reporting = ReportSubject(
                        kind: .chatMessage,
                        contentId: message.id,
                        contentDescription: message.content,
                        authorId: message.userId,
                        authorName: message.userName
                    )
                } label: {
                    Label("Report message", systemImage: "flag")
                }
                Button(role: .destructive) {
                    moderation.block(
                        message.userId.map { ModerationStore.Key.userId($0) }
                            ?? .displayName(message.userName),
                        displayName: message.userName
                    )
                } label: {
                    Label("Block \(message.userName)", systemImage: "person.slash")
                }
            }
        }
    }

    @ViewBuilder
    private func avatar(for message: IVSChatManager.Message) -> some View {
        Group {
            if let image = message.userImage, let url = URL(string: image) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { avatarFallback }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private var avatarFallback: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.14))
            Image(systemName: "person.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(StreamrFont.body())
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(sendDraft)

            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? StreamrColor.primary : .white.opacity(0.25))
            }
            // 44pt minimum touch target.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.25))
    }

    private var canSend: Bool {
        chat.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        let text = draft
        draft = ""
        chat.send(text)
    }
}

// ChatView.swift
// Text chat for the current Vail channel. Messages are in-memory only
// (cleared on channel switch, capped at 500 in VailSession). Outgoing
// chats trigger a reconnect if the server dropped us for inactivity —
// VailClient.sendChat handles that transparently.

import SwiftUI

struct ChatView: View {
    @EnvironmentObject var session: VailSession
    @State private var draft: String = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            composer
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            session.isChatViewActive = true
            session.markChatRead()
        }
        .onDisappear {
            session.isChatViewActive = false
        }
    }

    @ViewBuilder
    private var messagesList: some View {
        if session.chatMessages.isEmpty {
            ContentUnavailableView(
                "No messages",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Chat is per-channel and clears when you switch channels.")
            )
        } else {
            ScrollViewReader { proxy in
                List(session.chatMessages) { message in
                    ChatRow(
                        message: message,
                        isOwn: message.callsign == session.callsign
                    )
                    .id(message.id)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .onChange(of: session.chatMessages.count) { _, _ in
                    if let last = session.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = session.chatMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message #\(session.channel)", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 4)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit(send)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.sendChat(trimmed)
        draft = ""
    }
}

private struct ChatRow: View {
    let message: VailSession.ChatMessage
    let isOwn: Bool

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 40) }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !isOwn {
                        Text(message.callsign ?? "?")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if isOwn {
                        Text(message.callsign ?? "")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isOwn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    )
                    .textSelection(.enabled)
            }
            if !isOwn { Spacer(minLength: 40) }
        }
    }

    private var timeString: String {
        let date = Date(timeIntervalSince1970: TimeInterval(message.timestampMs) / 1000)
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// UnofficialNoticeView.swift
// First-launch acknowledgement that this is an unofficial third-party client.

import SwiftUI

struct UnofficialNoticeView: View {
    @AppStorage("hasAcknowledgedUnofficial") private var hasAcknowledged = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    Text("Unofficial App")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("""
                        This is an unofficial, community-built iOS client for the Vail morse code \
                        repeater network (vailmorse.com).
                        """)

                        Text("It is **not** made, maintained, or endorsed by the Vail project or its team.")

                        Text("""
                        Please send feedback, bug reports, and support requests to the \
                        **#ios-apps** channel in the Vail Discord (discord.gg/h28DefCf6J) — \
                        not to the broader Vail community or team.
                        """)

                        Text("""
                        The Vail repeater protocol may change at any time. When it does, this app may \
                        stop working until it is updated. There is no guarantee of timely updates or \
                        long-term maintenance.
                        """)

                        Text("Use at your own discretion.")
                            .italic()
                    }
                    .font(.body)
                    .foregroundStyle(.primary)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    hasAcknowledged = true
                } label: {
                    Text("I understand")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .interactiveDismissDisabled(true)
        }
    }
}

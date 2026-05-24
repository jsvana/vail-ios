// AboutView.swift
// About screen with disclaimer, version, and contact info.

import SwiftUI

struct AboutView: View {
    private let contactCallsign = "W6JY"
    private let contactEmail = "jaysvana@gmail.com"
    private let officialURL = URL(string: "https://vailmorse.com")!
    private let feedbackURL = URL(string: "https://discord.gg/h28DefCf6J")!

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Unofficial")
                            .font(.headline)
                    }
                    Text("""
                    This is an unofficial, community-built iOS client for the Vail morse code repeater \
                    network. It is not made, maintained, or endorsed by the Vail project or its team.
                    """)
                    Text("""
                    Please send feedback, bug reports, and support requests to the **#ios-apps** \
                    channel in the Vail Discord — not to the broader Vail community or team.
                    """)
                    Text("""
                    The Vail repeater protocol may change at any time. When it does, this app may stop \
                    working until it is updated. There is no guarantee of timely updates or long-term \
                    maintenance.
                    """)
                }
                .font(.callout)
                .padding(.vertical, 4)
            } header: {
                Text("Disclaimer")
            }

            Section("Feedback") {
                Link(destination: feedbackURL) {
                    LabeledContent("Discord") {
                        Text("#ios-apps")
                            .foregroundStyle(.tint)
                    }
                }
            }

            Section("Contact") {
                LabeledContent("Callsign") {
                    Text(contactCallsign)
                        .monospaced()
                }
                if let url = URL(string: "mailto:\(contactEmail)") {
                    Link(destination: url) {
                        LabeledContent("Email") {
                            Text(contactEmail)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }

            Section("Official Vail") {
                Link(destination: officialURL) {
                    LabeledContent("Website") {
                        Text("vailmorse.com")
                            .foregroundStyle(.tint)
                    }
                }
            }

            Section("Version") {
                LabeledContent("App") { Text(appVersionString).monospaced() }
                LabeledContent("Build") { Text(buildString).monospaced() }
            }
        }
        .navigationTitle("About")
    }

    private var appVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

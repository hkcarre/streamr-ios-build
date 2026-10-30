import SwiftUI

/// Lets someone see and undo their blocks.
///
/// Not optional polish: a block the person can't reverse is worse than no
/// block, and App Store review routinely checks that the control it asked for
/// under Guideline 1.2 is reachable and reversible rather than a one-way
/// switch buried in a menu.
///
/// Also the natural home for the published contact address, which 1.2 asks for
/// separately ("published contact information"). Putting it here means the
/// same screen answers both halves of the guideline.
struct BlockedAccountsView: View {
    @EnvironmentObject private var moderation: ModerationStore
    @State private var showingUnblockAllConfirm = false

    var body: some View {
        List {
            if moderation.blocked.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You haven't blocked anyone")
                            .font(StreamrFont.headline(15))
                        Text("Blocking someone hides their episodes and their live chat messages from you.")
                            .font(StreamrFont.body(13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    ForEach(moderation.blocked) { account in
                        HStack(spacing: 12) {
                            Image(systemName: "person.slash.fill")
                                .foregroundStyle(StreamrColor.grayText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(StreamrFont.body(15))
                                // Says which key the block used, because a
                                // name-only block is weaker and someone
                                // wondering why a message still appears
                                // deserves to know why.
                                Text(account.isNameOnly
                                     ? "Blocked by display name"
                                     : "Blocked account")
                                    .font(StreamrFont.body(12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unblock") {
                                moderation.unblock(account)
                            }
                            .font(StreamrFont.body(14))
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Blocked")
                } footer: {
                    Text("Blocks are stored on this device.")
                }

                Section {
                    Button("Unblock everyone", role: .destructive) {
                        showingUnblockAllConfirm = true
                    }
                }
            }

            Section {
                Link("Help & Support", destination: URL(string: "https://streamr.nyc/help-support")!)
                Button {
                    UIPasteboard.general.string = ReportSheet.contactAddress
                } label: {
                    HStack {
                        Text("Contact")
                        Spacer()
                        Text(ReportSheet.contactAddress)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Reporting a problem")
            } footer: {
                Text("To report an episode or a chat message, use the Report option on the episode or by holding down the message. Tap the address above to copy it.")
            }
        }
        .navigationTitle("Blocked accounts")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Unblock everyone?",
            isPresented: $showingUnblockAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Unblock everyone", role: .destructive) { moderation.unblockAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their episodes and chat messages will be visible to you again.")
        }
    }
}

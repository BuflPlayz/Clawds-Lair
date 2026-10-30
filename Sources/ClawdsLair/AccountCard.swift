import SwiftUI

struct AccountCard: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile
    /// Opens the account's activity page.
    var onShowDetails: () -> Void = {}
    @State private var editing = false
    @State private var confirmingRemove = false
    @State private var hovering = false
    @AppStorage(CardStyle.storageKey) private var style: CardStyle = .compact

    private var stats: ProfileStats? { store.stats[profile.id] }
    private var isActive: Bool { store.activeID == profile.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch style {
            case .compact: header
            case .portrait: portraitHeader
            }
            if let stats {
                details(stats)
            } else {
                HStack(spacing: 10) {
                    SparkView(state: .thinking, size: 22, color: profile.color)
                    Text("Reading sessions…").font(.sans(12)).foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                SwitchButton(profile: profile)
                Button(action: onShowDetails) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .help("Activity details")
                .accessibilityLabel("Activity details")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            if style == .portrait {
                PaletteGlow(colors: headerColors)
                    .frame(height: 150)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
                    .transition(.opacity)
            }
        }
        .glassCard(cornerRadius: 22, tint: isActive ? profile.color : nil)
        // No outline: the open account glows softly in its color, and hover deepens the shadow.
        .shadow(color: isActive ? profile.color.opacity(0.38) : .black.opacity(hovering ? 0.22 : 0.1),
                radius: isActive ? 26 : hovering ? 18 : 10, y: isActive ? 8 : 5)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
        .animation(.smooth(duration: 0.4), value: isActive)
        .animation(.smooth(duration: 0.35), value: style)
        .sheet(isPresented: $editing) { ProfileEditor(profile: profile) }
        .confirmationDialog("Remove \(profile.name)?", isPresented: $confirmingRemove) {
            Button("Move to Trash", role: .destructive) { store.remove(profile) }
        } message: {
            Text("Its folder (sign-in, settings, local data) goes to the Trash, so you can still restore it from there.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ProfileAvatar(profile: profile, image: store.avatars[profile.id], size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(profile.name).font(.serif(19)).lineLimit(1)
                    statusBadge
                }
                Text(subtitle).font(.sans(11)).foregroundStyle(Color.textTertiary).lineLimit(1)
            }
            Spacer()
            moreMenu
        }
    }

    /// The whole square profile picture, large, beside the name.
    private var portraitHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ProfileAvatar(profile: profile, image: store.avatars[profile.id], size: 96, square: true)
                .shadow(color: (headerColors.first ?? .black).opacity(0.35), radius: 12, y: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.serif(24)).lineLimit(1).minimumScaleFactor(0.8)
                statusBadge
                Text(activityText).font(.sans(11)).foregroundStyle(Color.textTertiary).lineLimit(1)
                Text(Fmt.bytes(stats?.folderBytes ?? 0)).font(.sans(11)).foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) { moreMenu }
    }

    /// The picture's main colors, or shades of the account color when there's no picture.
    private var headerColors: [Color] {
        if let colors = store.avatarColors[profile.id], !colors.isEmpty { return colors }
        return [profile.color, profile.color.opacity(0.55), profile.color.opacity(0.8)]
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isActive {
            Badge(text: "Open", color: profile.color, live: true)
        } else if !store.isClaudeRunning && store.residentID == profile.id {
            Badge(text: "Last used", color: .textSecondary)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Activity Details", systemImage: "chart.bar.xaxis") { onShowDetails() }
            Button("Edit…", systemImage: "pencil") { editing = true }
            Button("Show Folder in Finder", systemImage: "folder") { store.reveal(profile) }
            if profile.id != store.residentID {
                Divider()
                Button("Remove…", systemImage: "trash", role: .destructive) { confirmingRemove = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var subtitle: String {
        "\(activityText) · \(Fmt.bytes(stats?.folderBytes ?? 0))"
    }

    private var activityText: String {
        guard let last = stats?.lastActive else { return "Not used yet" }
        return "Active \(last.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))"
    }

    // MARK: Stats

    @ViewBuilder
    private func details(_ s: ProfileStats) -> some View {
        HStack(spacing: 6) {
            tile(Fmt.tokens(s.totals.total), "Tokens")
            tile(Fmt.tokens(s.totals.output), "Output")
            tile("\(s.sessions)", "Sessions")
            tile(Fmt.tokens(s.totals.messages), "Replies")
        }

        if let plan = s.planUsage, plan.fiveHour != nil || plan.weekly != nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    heading("Plan usage")
                    Spacer()
                    Text("Saved by Claude \(plan.at.formatted(.relative(presentation: .named)))")
                        .font(.sans(11))
                        .foregroundStyle(Color.textTertiary)
                        .help(PlanUsage.savedHelp)
                }
                if let fh = plan.fiveHour { meter("5-hour", fh) }
                if let wk = plan.weekly { meter("Weekly", wk) }
            }
        }

        if s.byModel.isEmpty {
            HStack(spacing: 8) {
                SparkView(size: 16, color: Color.textTertiary.opacity(0.6), ticklesOnTap: true)
                Text("No Claude Code or Cowork activity yet.")
                    .font(.sans(12))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            modelBreakdown(s)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.sans(12, .semibold)).foregroundStyle(Color.textSecondary)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.sans(15, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.sans(10)).foregroundStyle(Color.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .insetFill(cornerRadius: 11)
    }

    private func meter(_ label: String, _ percent: Int) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.sans(11)).foregroundStyle(Color.textSecondary).frame(width: 44, alignment: .leading)
            Meter(fraction: Double(percent) / 100,
                  color: percent >= 90 ? .red : percent >= 70 ? .orange : profile.color)
            Text("\(percent)%").font(.sans(11, .medium)).monospacedDigit().frame(width: 34, alignment: .trailing)
        }
    }

    private func modelBreakdown(_ s: ProfileStats) -> some View {
        let total = max(s.totals.total, 1)
        let models = s.byModel.sorted { $0.value.total > $1.value.total }.prefix(3)
        return VStack(alignment: .leading, spacing: 6) {
            heading("Models")
            ForEach(Array(models), id: \.key) { model, counts in
                HStack(spacing: 8) {
                    Text(Fmt.model(model)).font(.sans(11)).foregroundStyle(Color.textSecondary)
                        .frame(width: 72, alignment: .leading).lineLimit(1)
                    Meter(fraction: Double(counts.total) / Double(total), color: profile.color)
                    Text(Fmt.tokens(counts.total)).font(.sans(11, .medium)).monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
    }

}

// MARK: - Switch

/// Switches Claude to this account, or brings Claude forward if it's already open on it.
struct SwitchButton: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile
    var fullWidth = true

    private var isActive: Bool { store.activeID == profile.id }

    var body: some View {
        let button = Button {
            store.switchTo(profile)
        } label: {
            Text(title).font(.sans(13, .medium)).frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .controlSize(.large)
        .disabled(store.busyMessage != nil)

        if isActive {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.glassProminent).tint(profile.color)
        }
    }

    private var title: String {
        if isActive { return "Bring Claude to Front" }
        return store.isClaudeRunning ? "Switch to \(profile.name)" : "Open Claude as \(profile.name)"
    }
}

// MARK: - Avatar

/// The account's profile picture from Claude, or its initial on the account color.
/// The saved picture is square; it's shown as a circle, or uncropped as a rounded square.
struct ProfileAvatar: View {
    let profile: Profile
    let image: NSImage?
    var size: CGFloat = 32
    var square = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: square ? size * 0.22 : size / 2, style: .continuous)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ZStack {
                    profile.color.opacity(0.2)
                    Text(initial)
                        .font(.serif(size * 0.48, .medium))
                        .foregroundStyle(profile.color)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }

    private var initial: String {
        profile.name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

/// A soft, blurred mesh of a picture's main colors, fading out toward the bottom.
struct PaletteGlow: View {
    let colors: [Color]

    var body: some View {
        let c = colors.isEmpty ? [Color.clay] : colors
        let pick = { (i: Int) in c[i % c.count] }
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0],
                     [0, 0.5], [0.6, 0.45], [1, 0.5],
                     [0, 1], [0.5, 1], [1, 1]],
            colors: [pick(0), pick(1), pick(2),
                     pick(3), pick(0), pick(1),
                     pick(2), pick(3), pick(1)]
        )
        // Draw past the edges so the blur doesn't fade them; the caller clips to the card.
        .padding(-40)
        .blur(radius: 30)
        .opacity(0.45)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.4),
                                     .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .animation(.smooth(duration: 0.5), value: colors)
    }
}

// MARK: - Add / edit sheet

struct ProfileEditor: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let profile: Profile?

    @State private var name: String
    @State private var colorIndex: Int
    @State private var openAfterAdding = true
    @FocusState private var nameFocused: Bool

    init(profile: Profile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _colorIndex = State(initialValue: profile?.colorIndex ?? 1)
    }

    /// What the avatar will look like with the current edits.
    private var preview: Profile {
        var p = profile ?? .new(name: "", colorIndex: 0)
        p.name = name.isEmpty ? (profile?.name ?? "?") : name
        p.colorIndex = colorIndex
        return p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProfileAvatar(profile: preview, image: profile.flatMap { store.avatars[$0.id] }, size: 44)
                    .animation(.smooth, value: colorIndex)
                Text(profile == nil ? "Add an account" : "Edit account").font(.serif(26))
            }

            TextField("Name (e.g. Work, School)", text: $name)
                .textFieldStyle(.plain)
                .font(.sans(14))
                .focused($nameFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.surface, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(nameFocused ? Color.clay.opacity(0.6) : Color.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.sans(12, .medium)).foregroundStyle(Color.textSecondary)
                HStack(spacing: 8) {
                    ForEach(profilePalette.indices, id: \.self) { i in
                        Button { colorIndex = i } label: {
                            Circle().fill(profilePalette[i].gradient).frame(width: 22, height: 22)
                                .padding(3)
                                .overlay(Circle().strokeBorder(profilePalette[i], lineWidth: colorIndex == i ? 2 : 0))
                                .scaleEffect(colorIndex == i ? 1.08 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.smooth(duration: 0.2), value: colorIndex)
                Text("The account's Claude profile picture is used once it has signed in.")
                    .font(.sans(11))
                    .foregroundStyle(Color.textTertiary)
            }

            if profile == nil {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("Open Claude on this account now so I can sign in", isOn: $openAfterAdding)
                        .font(.sans(12))
                        .tint(.clay)
                    Text("If Claude is open, it will quit first. Your current account stays signed in and is one click away.")
                        .font(.sans(11))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(12)
                .insetFill(cornerRadius: 12)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                Button(profile == nil ? "Add Account" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .tint(.clay)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.sans(13, .medium))
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { nameFocused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if var existing = profile {
            existing.name = trimmed
            existing.colorIndex = colorIndex
            store.update(existing)
            dismiss()
        } else {
            let created = store.addProfile(name: trimmed, colorIndex: colorIndex)
            dismiss()
            if let created, openAfterAdding {
                // Let the sheet close before a possible confirmation alert appears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.switchTo(created) }
            }
        }
    }
}

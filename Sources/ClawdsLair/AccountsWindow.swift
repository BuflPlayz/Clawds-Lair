import SwiftUI

struct AccountsWindow: View {
    @EnvironmentObject var store: ProfileStore
    @State private var addingAccount = false
    @State private var sparkEntering = true
    /// The account whose activity page is showing, if any.
    @State private var detailID: UUID?
    /// True while the window animates between page sizes, so neither page's limits get in the way.
    @State private var resizing = false
    /// The list's window size, restored when coming back from an activity page.
    @State private var listSize: CGSize?
    /// Pages are hidden while the window resizes, so only the backdrop redraws each frame.
    @State private var contentVisible = true
    @State private var window = WindowRef()

    var body: some View {
        ZStack {
            if !contentVisible {
                Color.clear
            } else if let profile = store.profiles.first(where: { $0.id == detailID }) {
                page(maxWidth: 1080) {
                    AccountDetailView(profile: profile)
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            } else {
                page(maxWidth: 760) {
                    VStack(alignment: .leading, spacing: 20) {
                        hero
                        ActivityOverview()
                        accounts
                        Text("Stats come from Claude Code and Cowork sessions on this Mac; regular chats live on Claude's servers and aren't counted.")
                            .font(.sans(11))
                            .foregroundStyle(Color.textTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .toolbar { toolbarItems }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background { backdrop }
        .background(WindowReader(ref: window))
        .frame(minWidth: widthRange.lowerBound, maxWidth: widthRange.upperBound, minHeight: 520)
        .onChange(of: store.profiles) { _, profiles in
            if let id = detailID, !profiles.contains(where: { $0.id == id }) { closeDetails() }
        }
        .overlay { busyOverlay }
        .animation(.smooth(duration: 0.3), value: store.busyMessage)
        .sheet(isPresented: $addingAccount) { ProfileEditor(profile: nil) }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task {
            store.refreshActive()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                store.refreshStats()
            }
        }
    }

    // MARK: Pages

    private func page<Content: View>(maxWidth: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            // One container renders all of the page's glass together, which is cheaper while
            // scrolling than each card sampling the backdrop on its own. Spacing 0 keeps
            // neighbouring cards from merging into each other.
            GlassEffectContainer(spacing: 0) {
                content()
            }
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private static let listWidths: ClosedRange<CGFloat> = 560...760
    private static let detailWidths: ClosedRange<CGFloat> = 820...1120
    private static let detailSize = CGSize(width: 980, height: 860)

    private var widthRange: ClosedRange<CGFloat> {
        if resizing { return Self.listWidths.lowerBound...Self.detailWidths.upperBound }
        return detailID == nil ? Self.listWidths : Self.detailWidths
    }

    private func showDetails(_ id: UUID) {
        listSize = window.window?.frame.size
        let height = max(listSize?.height ?? 0, Self.detailSize.height)
        navigate(to: id, size: CGSize(width: Self.detailSize.width, height: height))
    }

    private func closeDetails() {
        navigate(to: nil, size: listSize ?? CGSize(width: Self.listWidths.upperBound, height: 760))
    }

    /// Switches page and animates the window to fit it, growing or shrinking around its center.
    ///
    /// Re-laying out a full page on every frame of a window resize stutters, so the current page
    /// fades out first, the window resizes over just the backdrop, and the new page fades in.
    private func navigate(to id: UUID?, size: CGSize) {
        guard !resizing else { return }
        resizing = true
        withAnimation(.easeOut(duration: 0.14)) { contentVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            detailID = id
            guard let window = window.window else { finishNavigation(); return }
            var frame = window.frame
            let target = CGSize(width: size.width, height: size.height)
            frame.origin.x = frame.midX - target.width / 2
            frame.origin.y = frame.maxY - target.height
            frame.size = target
            if let screen = window.screen?.visibleFrame {
                frame.size.width = min(frame.width, screen.width)
                frame.size.height = min(frame.height, screen.height)
                frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
                frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
                window.animator().setFrame(frame, display: true)
            } completionHandler: {
                finishNavigation()
            }
        }
    }

    private func finishNavigation() {
        resizing = false
        withAnimation(.easeOut(duration: 0.24)) { contentVisible = true }
    }

    // MARK: Chrome

    /// Window toolbar items: macOS lines them up with the traffic lights, insets them like any
    /// native toolbar and draws them as glass. Content scrolls underneath with a soft edge.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if detailID != nil {
            ToolbarItem(placement: .navigation) {
                Button(action: closeDetails) {
                    Label("Accounts", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.sans(12, .medium))
                }
                .keyboardShortcut(.cancelAction)
                .help("Back to accounts")
            }
        }
        if store.isLoadingStats {
            ToolbarItem(placement: .principal) {
                loadingLabel
            }
        }
        ToolbarSpacer(.flexible)
        ToolbarItemGroup {
            Button {
                store.refreshActive()
                store.refreshStats()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isLoadingStats ? 360 : 0))
                    .animation(store.isLoadingStats ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.isLoadingStats)
            }
            .help("Refresh stats")
            .disabled(store.isLoadingStats)

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Button {
                addingAccount = true
            } label: {
                Label("Add Account", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.sans(12, .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(.clay)
        }
        // Match the inset the traffic lights get on the other side.
        ToolbarSpacer(.fixed)
    }

    /// Says the numbers on screen are about to change: last launch's cached stats, or a refresh.
    private var loadingLabel: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(store.stats.isEmpty ? "Loading stats…" : "Updating stats…")
        }
        .font(.sans(11, .medium))
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 10)
        .fixedSize()
    }

    /// Claude's warm canvas with soft light behind the glass, so the panels have something to refract.
    private var backdrop: some View {
        ZStack {
            Color.canvas
            RadialGradient(colors: [Color.clay.opacity(0.11), .clear], center: .init(x: 0.5, y: -0.05),
                           startRadius: 0, endRadius: 520)
            RadialGradient(colors: [(store.activeProfile?.color ?? .clay).opacity(0.06), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.6), value: store.activeID)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SparkView(state: heroSpark, size: 30, ticklesOnTap: true) { sparkEntering = false }
                Text(greeting).font(.serif(30))
            }
            statusPill
        }
        .frame(maxWidth: .infinity)
    }

    private var heroSpark: SparkState {
        if sparkEntering { return .entrance }
        if store.busyMessage != nil { return .writing }
        return store.isLoadingStats ? .thinking : .idle
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<24: "Good evening"
        default: "Up late"
        }
        guard let first = NSFullUserName().split(separator: " ").first else { return part }
        return "\(part), \(first)"
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            if let active = store.activeProfile {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Claude is open as")
                ProfileAvatar(profile: active, image: store.avatars[active.id], size: 16)
                Text(active.name).font(.sans(12, .semibold))
            } else {
                Circle().fill(Color.textTertiary).frame(width: 6, height: 6)
                Text("Claude isn't running")
            }
        }
        .font(.sans(12))
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: Accounts

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Accounts", trailing: store.profiles.count == 1 ? "1 account" : "\(store.profiles.count) accounts")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 14) {
                ForEach(store.profiles) { profile in
                    AccountCard(profile: profile) { showDetails(profile.id) }
                }
            }
        }
    }

    // MARK: Busy

    @ViewBuilder
    private var busyOverlay: some View {
        if let busy = store.busyMessage {
            ZStack {
                Rectangle().fill(.black.opacity(0.18)).ignoresSafeArea()
                VStack(spacing: 14) {
                    ClawdView(animation: .running, loops: true, scale: 3)
                        .padding(.top, 6)
                    Text(busy).font(.serif(20))
                    Text("Your other accounts stay signed in.")
                        .font(.sans(12))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .glassCard(cornerRadius: 28)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

/// Holds the hosting window so the page switch can animate its size.
final class WindowRef {
    weak var window: NSWindow?
}

private struct WindowReader: NSViewRepresentable {
    let ref: WindowRef

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { ref.window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if ref.window == nil { ref.window = view.window }
    }
}

/// The combined activity calendar with a per-account filter. Its hover and filter state live
/// here so hovering the calendar doesn't rebuild the rest of the window.
private struct ActivityOverview: View {
    @EnvironmentObject var store: ProfileStore
    /// Which account the calendar shows; nil means all of them combined.
    @State private var activityFilter: UUID?
    @State private var hoveredDay: Date?

    private var selectedProfile: Profile? {
        store.profiles.first { $0.id == activityFilter }
    }

    private var activityDaily: [String: Int] {
        if let selectedProfile { return store.stats[selectedProfile.id]?.daily ?? [:] }
        var combined: [String: Int] = [:]
        for stats in store.stats.values {
            for (day, tokens) in stats.daily { combined[day, default: 0] += tokens }
        }
        return combined
    }

    var body: some View {
        let daily = activityDaily
        let color = selectedProfile?.color ?? .clay
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Activity")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if store.profiles.count > 1 { activityFilters }
                    Spacer(minLength: 8)
                    Text(activityCaption(daily))
                        .font(.sans(12))
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                ActivityCalendar(daily: daily, color: color, hovered: $hoveredDay)
                HStack {
                    Text("Tokens per day from Claude Code and Cowork")
                        .font(.sans(10))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    ActivityLegend(color: color)
                }
            }
            .padding(16)
            .glassCard(cornerRadius: 22)
            // Clawd stands on the card's top edge.
            .overlay(alignment: .topTrailing) {
                ClawdBuddy()
                    .alignmentGuide(.top) { $0[.bottom] }
                    .padding(.trailing, 28)
            }
        }
        .onChange(of: store.profiles) { _, profiles in
            if let id = activityFilter, !profiles.contains(where: { $0.id == id }) { activityFilter = nil }
        }
    }

    private func activityCaption(_ daily: [String: Int]) -> String {
        if let day = hoveredDay {
            let tokens = daily[DayKey.string(day)] ?? 0
            let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
            return tokens > 0 ? "\(date) · \(Fmt.tokens(tokens)) tokens" : "\(date) · No activity"
        }
        let summary = ActivitySummary(daily: daily, days: 365)
        var parts = ["Active \(summary.activeDays) of the last 365 days"]
        if summary.streak > 1 { parts.append("\(summary.streak)-day streak") }
        return parts.joined(separator: " · ")
    }

    private var activityFilters: some View {
        HStack(spacing: 6) {
                GlassChip(selected: activityFilter == nil, tint: .clay) {
                    activityFilter = nil
                } label: {
                    Text("All")
                }
                ForEach(store.profiles) { profile in
                    GlassChip(selected: activityFilter == profile.id, tint: profile.color) {
                        activityFilter = profile.id
                    } label: {
                        HStack(spacing: 5) {
                            ProfileAvatar(profile: profile, image: store.avatars[profile.id], size: 14)
                            Text(profile.name)
                        }
                    }
                }
        }
        .font(.sans(12, .medium))
        .animation(.smooth(duration: 0.25), value: activityFilter)
    }
}

import SwiftUI
import AppKit
import SwitchCore

enum PanelLayout {
    static let width: CGFloat = 264
    static let rowHeight: CGFloat = 26
    static let maxVisibleRows = 6
}

enum NoticeKind { case neutral, success, error }

private enum Palette {
    static let accent = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.40, green: 0.85, blue: 0.73, alpha: 1) : NSColor(red: 0.08, green: 0.43, blue: 0.35, alpha: 1) })
    static let canvas = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1) : NSColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1) })
    static let line = Color.primary.opacity(0.08)
    static let warning = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 1, green: 0.70, blue: 0.38, alpha: 1) : NSColor(red: 0.60, green: 0.29, blue: 0.06, alpha: 1) })
}

/// Compact menu-bar panel: one line per account, the signed-in account with its quota on top,
/// click a row to switch. Height follows the content.
struct Panel: View {
    @ObservedObject var model: Model
    // Presentation only: enabled exclusively for offscreen renders with synthetic data.
    private let productPreview: Bool
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weeklyFirst") private var weeklyFirst = true
    init(model: Model, expanded: Bool = false, productPreview: Bool = false) {
        self.model = model
        self.productPreview = productPreview && model.isDemo && CommandLine.arguments.contains("--render-preview")
    }
    private var active: Profile? { model.profiles.first { $0.id == model.current } }
    private var others: [Profile] { model.profiles.filter { $0.id != model.current } }

    var body: some View {
        VStack(spacing: 0) {
            if model.isDemo && !productPreview { demoStrip }
            if let active { currentRow(active) } else { emptyCurrent }
            Divider()
            if others.isEmpty {
                Text(model.isDemo ? L10n.text("다른 계정을 추가하면 클릭 한 번으로 선택할 수 있어요.") : L10n.text("계정 추가 → 다른 계정으로 로그인…으로 추가하세요. 로그아웃은 필요 없습니다."))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            } else if others.count > PanelLayout.maxVisibleRows {
                ScrollView { rows }.frame(height: CGFloat(PanelLayout.maxVisibleRows) * PanelLayout.rowHeight + 8)
            } else { rows }
            if model.busy || model.loginInProgress || model.notice != .neutral || model.recovery { notice }
            Divider()
            footer
        }
        .frame(width: PanelLayout.width)
        .background(Palette.canvas)
        .tint(Palette.accent)
    }

    private var demoStrip: some View {
        HStack(spacing: 6) {
            Text("DEMO").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 2).overlay(Capsule().strokeBorder(Palette.line))
                .accessibilityLabel(L10n.text("데모 모드"))
            Text(L10n.text("샘플 계정만 바뀝니다")).font(.system(size: 9.5)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
    }

    private var emptyCurrent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(L10n.text("저장된 현재 계정 없음"), systemImage: "person.crop.circle.badge.questionmark").font(.system(size: 11.5, weight: .medium))
            Text(L10n.text("로그인한 계정을 저장하면 여기에 표시됩니다.")).font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currentRow(_ profile: Profile) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in currentContent(profile, now: context.date) }
    }
    private func currentContent(_ profile: Profile, now: Date) -> some View {
        let usage = model.usage[profile.id]
        let window = usage.flatMap { orderedWindows($0).first }
        let schedule = ResetSchedule(timestamp: window?.resetsAt, now: now, language: L10n.language)
        let remaining: Double? = schedule.needsRefresh ? nil : window?.remainingPercent
        let detail = detailLabel(usage: usage, window: window, schedule: schedule)
        let warning = schedule.needsRefresh && window != nil
        return VStack(alignment: .leading, spacing: 3) {
            titleLine(profile, usage: usage, remaining: remaining)
            detailLine(left: detail.left, right: detail.right, help: detail.help, warning: warning)
            if window != nil { quotaBar(remaining) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Palette.accent.opacity(0.06))
        .contextMenu { Button(L10n.text("이름 변경…")) { model.rename(profile) } }
        .help(profile.name + " · " + profile.email)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("현재 선택됨") + ", " + profile.name + ", " + profile.email)
    }
    private func titleLine(_ profile: Profile, usage: UsageSnapshot?, remaining: Double?) -> some View {
        HStack(spacing: 7) {
            avatar(profile, size: 22, active: true)
            Text(profile.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            planBadge(profile)
            Spacer(minLength: 6)
            percentLabel(usage: usage, remaining: remaining, size: 14)
        }
    }
    private func detailLine(left: String, right: String, help: String, warning: Bool) -> some View {
        HStack(spacing: 6) {
            Text(left).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text(right).font(.system(size: 10)).lineLimit(1).fixedSize().foregroundStyle(warning ? Palette.warning : Color.secondary)
        }.help(help)
    }
    private func quotaBar(_ remaining: Double?) -> some View {
        GeometryReader { geometry in
            Capsule().fill(Palette.accent.opacity(0.12))
            Capsule().fill((remaining ?? 100) <= 20 ? Palette.warning : Palette.accent)
                .frame(width: geometry.size.width * (remaining ?? 0) / 100)
        }.frame(height: 3).padding(.top, 2).accessibilityHidden(true)
    }

    private var rows: some View {
        VStack(spacing: 0) { ForEach(others) { profile in otherRow(profile) } }.padding(.vertical, 4)
    }
    private func otherRow(_ profile: Profile) -> some View {
        let usage = model.usage[profile.id]
        let window = usage.flatMap { orderedWindows($0).first }
        let schedule = ResetSchedule(timestamp: window?.resetsAt, now: Date(), language: L10n.language)
        let remaining: Double? = window.flatMap { $0.resetPassed(at: Date()) ? nil : $0.remainingPercent }
        return Button { model.switchTo(profile) } label: {
            HStack(spacing: 7) {
                avatar(profile, size: 18, active: false)
                Text(profile.name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
                planBadge(profile)
                Spacer(minLength: 6)
                if window != nil, !schedule.remainingLabel.isEmpty, !schedule.needsRefresh {
                    Text(schedule.remainingLabel).font(.system(size: 9.5)).foregroundStyle(.secondary).fixedSize().help(schedule.compactLabel)
                }
                percentLabel(usage: usage, remaining: remaining, size: 11.5)
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.horizontal, 10).frame(height: PanelLayout.rowHeight).contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle()).disabled(model.busy || model.recovery || model.loginInProgress)
        .help(L10n.format("%@ 계정으로 전환", profile.email))
        .accessibilityLabel(L10n.format("%@, %@, 계정 전환", profile.name, profile.email))
        .contextMenu { Button(L10n.text("이름 변경…")) { model.rename(profile) } }
    }

    private func avatar(_ profile: Profile, size: CGFloat, active: Bool) -> some View {
        let colors: [Color] = [Palette.accent, colorScheme == .dark ? .purple : .indigo, .orange, .blue]
        let index = Int(profile.id.prefix(2), radix: 16) ?? 0
        let color = active ? Palette.accent : colors[index % colors.count]
        return Text(String(profile.name.prefix(1))).font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(color).frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }

    @ViewBuilder private func planBadge(_ profile: Profile) -> some View {
        if let usage = model.usage[profile.id], usage.plan != nil {
            Text(usage.planLabel).font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Palette.accent).padding(.horizontal, 4).padding(.vertical, 1.5)
                .background(Palette.accent.opacity(0.09), in: Capsule()).fixedSize()
                .help(usage.isDemo ? L10n.text("샘플 요금제") : L10n.text("마지막 확인한 요금제"))
        }
    }

    private func percentLabel(usage: UsageSnapshot?, remaining: Double?, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if let marker = marker(usage) { Text(marker).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary) }
            Text(remaining.map { "\(Int($0.rounded(.down)))%" } ?? "—")
                .font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(usage == nil ? Color.secondary : (remaining ?? 100) <= 20 ? Palette.warning : Color.primary)
        }.fixedSize().help(usage.map(usageCaption) ?? L10n.text("사용량 미확인"))
    }
    private func marker(_ usage: UsageSnapshot?) -> String? {
        guard let usage, !productPreview else { return nil }
        switch usage.source {
        case .demo: return "D"
        case .sessionLog: return L10n.text("기록")
        case .live: return usage.isStale(at: Date()) ? "~" : nil
        }
    }
    private func detailLabel(usage: UsageSnapshot?, window: UsageWindow?, schedule: ResetSchedule) -> (left: String, right: String, help: String) {
        if let window { return (window.title + " · " + schedule.compactLabel, schedule.remainingLabel, schedule.fullLabel) }
        if model.isDemo { return (L10n.text("사용량 미확인"), "", L10n.text("사용량 미확인 · 실시간 조회 연결 전")) }
        let text = model.liveUsageError ?? L10n.text("사용량 기록 없음 · Codex를 사용하면 표시됩니다")
        return (text, "", text)
    }
    private func usageCaption(_ usage: UsageSnapshot) -> String {
        if productPreview { return L10n.text("한국 시간 (KST)") }
        switch usage.source {
        case .demo: return L10n.text("샘플 사용량 · 한국 시간 (KST)")
        case .sessionLog: return L10n.format("Codex 세션 기록 · 마지막 %@", recordedLabel(usage.observedAt))
        case .live:
            return usage.isStale(at: Date()) ? L10n.text("마지막 확인 값 · 새로고침 필요") : L10n.format("마지막 확인 %@", String(usage.observedAt.formatted(date: .omitted, time: .shortened)))
        }
    }
    private func recordedLabel(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .shortened)
    }
    private func orderedWindows(_ usage: UsageSnapshot) -> [UsageWindow] {
        guard weeklyFirst else { return usage.windows }
        return usage.windows.filter { $0.windowDurationMins == 10080 } + usage.windows.filter { $0.windowDurationMins != 10080 }
    }

    private var notice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if model.busy || model.loginInProgress { ProgressView().controlSize(.mini) }
            else { Image(systemName: model.notice == .error ? "exclamationmark.circle" : "checkmark.circle").font(.system(size: 10)) }
            Text(model.message).font(.system(size: 10.5)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if model.loginInProgress {
                Button(L10n.text("취소"), action: model.cancelLogin).controlSize(.mini)
            } else if model.recovery {
                Button(L10n.text("복구"), action: model.restore).controlSize(.mini).disabled(model.busy)
            } else if !model.busy {
                Button { model.notice = .neutral } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16) }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("안내 닫기"))
            }
        }.foregroundStyle(model.notice == .error ? Palette.warning : Palette.accent)
            .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            .background((model.notice == .error ? Palette.warning : Palette.accent).opacity(0.07))
    }

    private var footer: some View {
        HStack(spacing: 2) {
            if !model.isDemo || productPreview {
                Menu {
                    Button(L10n.text("다른 계정으로 로그인…"), action: model.loginAnotherAccount)
                    Button(L10n.text("현재 로그인 계정 추가"), action: model.saveCurrent)
                    Button(L10n.text("로그인 파일 가져오기…"), action: model.importAccount)
                } label: {
                    Label(L10n.text("계정 추가"), systemImage: "plus").font(.system(size: 11)).padding(.horizontal, 2)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary)
                    .help(L10n.text("다른 계정으로 로그인…")).disabled(model.busy || model.loginInProgress)
            }
            Spacer(minLength: 0)
            Button { model.refresh(); model.refreshLiveUsage(force: true) } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11)).frame(width: 22, height: 22)
            }.buttonStyle(.plain).help(L10n.text("계정 새로고침")).accessibilityLabel(L10n.text("계정 새로고침")).disabled(model.busy)
            Menu {
                Toggle(L10n.text("주간 우선 표시"), isOn: $weeklyFirst)
                Toggle(L10n.text("메뉴바에 잔여량 표시"), isOn: $model.menuUsageEnabled)
                if model.isDemo {
                    Divider()
                    Picker(L10n.text("전환 시나리오"), selection: $model.scenario) {
                        ForEach(DemoScenario.allCases) { Text($0.title).tag($0) }
                    }
                }
                Divider()
                Menu("Language / 언어") {
                    Button("System / 시스템") { UserDefaults.standard.removeObject(forKey: "appLanguage") }
                    Button("한국어") { UserDefaults.standard.set("ko", forKey: "appLanguage") }
                    Button("English") { UserDefaults.standard.set("en", forKey: "appLanguage") }
                    Text("Restart app to apply / 재실행 후 적용")
                }
                Divider()
                Button(model.isDemo ? L10n.text("실제 계정 모드로 전환 (재실행)") : L10n.text("데모 모드로 전환 (재실행)")) { model.switchMode(toLive: model.isDemo) }
                Button(L10n.text("Codex Account Toggle 종료")) { NSApp.terminate(nil) }
            } label: { Image(systemName: "gearshape").font(.system(size: 11)).frame(width: 22, height: 22) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(L10n.text("앱 설정")).accessibilityLabel(L10n.text("앱 설정")).disabled(model.busy)
        }.foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 3)
    }
}

private struct RowButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Palette.accent.opacity(configuration.isPressed ? 0.14 : hovered ? 0.07 : 0))
            .onHover { hovered = $0 }
    }
}

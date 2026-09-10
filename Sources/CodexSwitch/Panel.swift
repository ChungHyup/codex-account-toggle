import SwiftUI
import AppKit
import SwitchCore

enum NoticeKind { case neutral, success, error }

private enum Palette {
    static let accent = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.40, green: 0.85, blue: 0.73, alpha: 1) : NSColor(red: 0.08, green: 0.43, blue: 0.35, alpha: 1) })
    static let canvas = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1) : NSColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1) })
    static let card = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.08)
    static let warning = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 1, green: 0.70, blue: 0.38, alpha: 1) : NSColor(red: 0.60, green: 0.29, blue: 0.06, alpha: 1) })
}

struct Panel: View {
    @ObservedObject var model: Model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDemoSettings = false
    init(model: Model, expanded: Bool = false) {
        self.model = model
        _showDemoSettings = State(initialValue: expanded)
    }
    private var active: Profile? { model.profiles.first { $0.id == model.current } }
    private var others: [Profile] { model.profiles.filter { $0.id != model.current } }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 20) {
                if let active { currentCard(active) }
                else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.text("저장된 현재 계정 없음"), systemImage: "person.crop.circle.badge.questionmark").font(.system(size: 14, weight: .semibold))
                        Text(L10n.text("로그인한 계정을 저장하면 여기에 표시됩니다.")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.text("계정 전환")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(L10n.format("%@개 계정", String(others.count))).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 3)
                    if others.isEmpty {
                        Text(L10n.text("다른 계정을 추가하면 클릭 한 번으로 선택할 수 있어요."))
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(16)
                    } else if others.count > 3 {
                        ScrollView { accountRows }.frame(height: 220)
                    } else { accountRows }
                }
                if model.busy || model.notice != .neutral || model.recovery { notice }
                if model.recovery {
                    Button(L10n.text("이전 로그인 복구"), action: model.restore).buttonStyle(.borderedProminent).tint(Palette.accent).disabled(model.busy)
                }
                if !model.isDemo {
                    Button(action: model.saveCurrent) {
                        Label(L10n.text("현재 로그인 계정 추가"), systemImage: "plus").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.bordered).disabled(model.busy)
                }
            }.padding(.horizontal, 20).padding(.bottom, 20)
            Spacer(minLength: 0)
            if model.isDemo { demoArea }
            footer
        }
        .frame(width: 380)
        .frame(minHeight: 680 + (showDemoSettings ? 44 : 0) + (model.busy || model.notice != .neutral || model.recovery ? 56 : 0))
        .background(Palette.canvas)
        .tint(Palette.accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.canvas)
                .frame(width: 32, height: 32).background(Color.primary, in: RoundedRectangle(cornerRadius: 10))
            Text("Codex Switch").font(.system(size: 16, weight: .semibold, design: .rounded)).tracking(-0.4)
            Spacer()
            if model.isDemo {
                Text("DEMO").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                    .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(Palette.line)).accessibilityLabel(L10n.text("데모 모드"))
            }
        }.padding(20)
    }

    private func currentCard(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(Palette.accent).frame(width: 5, height: 5)
                Text(model.isDemo ? L10n.text("현재 선택한 데모 계정") : L10n.text("현재 로그인 계정"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                Spacer()
                options(profile)
            }
            HStack(spacing: 12) {
                avatar(profile, active: true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(profile.name).font(.system(size: 20, weight: .semibold)).tracking(-0.5).lineLimit(1).help(profile.name)
                        planBadge(profile)
                    }
                    Text(profile.email).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).help(profile.email)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundStyle(Palette.accent)
                    .accessibilityLabel(L10n.text("현재 선택됨"))
            }
            Rectangle().fill(Palette.accent.opacity(0.12)).frame(height: 1)
            if let usage = model.usage[profile.id] {
                HStack(alignment: .top, spacing: 16) {
                    if let primary = usage.limit?.primary { quotaMeter(primary, fallback: primary.title) }
                    if let secondary = usage.limit?.secondary { quotaMeter(secondary, fallback: secondary.title) }
                }
                Text(usage.isDemo ? L10n.text("샘플 사용량 · 한국 시간 (KST)") : usage.isStale(at: Date()) ? L10n.text("마지막 확인 값 · 새로고침 필요") : L10n.format("마지막 확인 %@", String(usage.observedAt.formatted(date: .omitted, time: .shortened))))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text(L10n.text("사용량 미확인 · 실시간 조회 연결 전")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(18)
            .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.accent.opacity(0.15)))
    }

    private var accountRows: some View {
        VStack(spacing: 8) {
            ForEach(others) { profile in
                HStack(spacing: 0) {
                    Button { model.switchTo(profile) } label: {
                        HStack(spacing: 11) {
                            avatar(profile, active: false)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(profile.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                                    planBadge(profile)
                                }
                                Text(profile.email).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                if let usage = model.usage[profile.id] {
                                    Text(compactUsage(usage)).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.accent)
                                } else {
                                    Text(L10n.text("요금제·사용량 미확인")).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        }.padding(.leading, 13).padding(.vertical, 13).padding(.trailing, 8).contentShape(Rectangle())
                    }.buttonStyle(AccountButtonStyle()).disabled(model.busy || model.recovery)
                        .help(L10n.format("%@ 계정으로 전환", String(profile.name)))
                        .accessibilityLabel(L10n.format("%@, %@, 계정 전환", String(profile.name), String(profile.email)))
                    options(profile).padding(.trailing, 9)
                }.background(Palette.card, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line))
            }
        }
    }

    private func avatar(_ profile: Profile, active: Bool) -> some View {
        let colors: [Color] = [Palette.accent, colorScheme == .dark ? .purple : .indigo, .orange, .blue]
        let index = Int(profile.id.prefix(2), radix: 16) ?? 0
        let color = active ? Palette.accent : colors[index % colors.count]
        return Text(String(profile.name.prefix(1))).font(.system(size: active ? 19 : 14, weight: .semibold))
            .foregroundStyle(color).frame(width: active ? 46 : 36, height: active ? 46 : 36)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: active ? 14 : 11))
            .accessibilityHidden(true)
    }

    @ViewBuilder private func planBadge(_ profile: Profile) -> some View {
        if let usage = model.usage[profile.id], usage.plan != nil {
            Text(usage.planLabel).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.accent).padding(.horizontal, 6).padding(.vertical, 3)
                .background(Palette.accent.opacity(0.09), in: Capsule())
                .help(usage.isDemo ? L10n.text("샘플 요금제") : L10n.text("마지막 확인한 요금제"))
        }
    }

    private func quotaMeter(_ window: UsageWindow?, fallback: String) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let schedule = ResetSchedule(timestamp: window?.resetsAt, now: context.date, language: L10n.language)
            let remaining = schedule.needsRefresh ? nil : window?.remainingPercent
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(window?.title ?? fallback).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text(remaining.map { "\(Int($0.rounded(.down)))%" } ?? "—")
                        .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(L10n.text("남음")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    Capsule().fill(Palette.accent.opacity(0.10))
                    Capsule().fill((remaining ?? 100) <= 20 ? Palette.warning : Palette.accent)
                        .frame(width: geometry.size.width * (remaining ?? 0) / 100)
                }.frame(height: 4).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(schedule.dateLabel).font(.system(size: 11, weight: .medium))
                    if !schedule.timeLabel.isEmpty {
                        Text(schedule.timeLabel).font(.system(size: 11)).monospacedDigit()
                    }
                    if !schedule.remainingLabel.isEmpty {
                        Text(schedule.remainingLabel).font(.system(size: 10))
                            .foregroundStyle(schedule.needsRefresh ? Palette.warning : .secondary)
                    }
                }.foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).help(schedule.fullLabel)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func compactUsage(_ usage: UsageSnapshot) -> String {
        let windows = [usage.limit?.primary, usage.limit?.secondary].compactMap { $0 }
        let text = windows.map { window in
            let percent = window.resetPassed(at: Date()) ? nil : window.remainingPercent
            return "\(window.title) \(percent.map { "\(Int($0.rounded(.down)))%" } ?? "—")"
        }.joined(separator: " · ")
        return text.isEmpty ? L10n.text("사용량 미확인") : (usage.isDemo ? L10n.text("샘플 · ") : L10n.text("마지막 확인 · ")) + text + L10n.text(" 남음")
    }

    private func options(_ profile: Profile) -> some View {
        Menu { Button(L10n.text("이름 변경…")) { model.rename(profile) } } label: {
            Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(model.busy)
            .help(L10n.format("%@ 관리", String(profile.name))).accessibilityLabel(L10n.format("%@ 관리", String(profile.name)))
    }

    private var notice: some View {
        HStack(alignment: .top, spacing: 8) {
            if model.busy { ProgressView().controlSize(.small) }
            else { Image(systemName: model.notice == .error ? "exclamationmark.circle" : "checkmark.circle").font(.system(size: 13)) }
            Text(model.message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(model.notice == .error ? Palette.warning : Palette.accent)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background((model.notice == .error ? Palette.warning : Palette.accent).opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var demoArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 12)).foregroundStyle(Palette.accent).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("안심하고 둘러보세요")).font(.system(size: 11, weight: .medium))
                    Text(L10n.text("샘플 계정만 바뀌며 실제 로그인은 유지됩니다.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { showDemoSettings.toggle() } label: {
                    Image(systemName: showDemoSettings ? "chevron.up" : "slider.horizontal.3")
                        .font(.system(size: 12)).frame(width: 26, height: 26)
                }.buttonStyle(.plain).foregroundStyle(.secondary).help(L10n.text("데모 테스트 설정"))
                    .accessibilityLabel(showDemoSettings ? L10n.text("데모 설정 접기") : L10n.text("데모 설정 펼치기"))
            }
            if showDemoSettings {
                Picker(L10n.text("전환 시나리오"), selection: $model.scenario) {
                    ForEach(DemoScenario.allCases) { Text($0.title).tag($0) }
                }.font(.system(size: 11)).disabled(model.busy)
            }
        }.padding(.horizontal, 20).padding(.vertical, 15)
            .background(Palette.accent.opacity(0.035))
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var footer: some View {
        HStack {
            Label(L10n.text("로컬 저장"), systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button(action: model.refresh) { Image(systemName: "arrow.clockwise").frame(width: 26, height: 26) }
                .buttonStyle(.plain).help(L10n.text("계정 새로고침")).accessibilityLabel(L10n.text("계정 새로고침")).disabled(model.busy)
            Menu {
                Menu("Language / 언어") {
                    Button("System / 시스템") { UserDefaults.standard.removeObject(forKey: "appLanguage") }
                    Button("한국어") { UserDefaults.standard.set("ko", forKey: "appLanguage") }
                    Button("English") { UserDefaults.standard.set("en", forKey: "appLanguage") }
                    Text("Restart Switch to apply / 재실행 후 적용")
                }
                Divider()
                if !model.isDemo { Button(L10n.text("로그인 파일 가져오기…"), action: model.importAccount) }
                Button(L10n.text("Codex Switch 종료")) { NSApp.terminate(nil) }
            } label: { Image(systemName: "gearshape").frame(width: 26, height: 26) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.text("앱 설정")).accessibilityLabel(L10n.text("앱 설정")).disabled(model.busy)
        }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8)
    }
}

private struct AccountButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Palette.accent.opacity(configuration.isPressed ? 0.12 : hovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 12))
            .onHover { hovered = $0 }
    }
}

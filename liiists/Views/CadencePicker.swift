import SwiftUI

/// Reusable streak-cadence control: a 2×2 segmented picker
/// (Daily · Weekdays · X/day · X/week) with a stepper that appears for the
/// count-based options. Used both when creating a streak (NewListSheet) and
/// when changing an existing streak's cadence (StreakListView).
struct CadencePicker: View {
    @Binding var cadence: StreakCadence
    @Environment(\.colorScheme) private var colorScheme

    private enum CadenceKind { case daily, weekdays, perDay, perWeek }

    private var cadenceKind: CadenceKind {
        switch cadence {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .timesPerDay: return .perDay
        case .timesPerWeek: return .perWeek
        }
    }

    // Stepper values, defaulting sensibly when the current cadence isn't that kind.
    private var perDayN: Int { if case .timesPerDay(let n) = cadence { return n }; return 2 }
    private var perWeekN: Int { if case .timesPerWeek(let n) = cadence { return n }; return 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceSM) {
            Text("CADENCE")
                .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cadenceButton(label: "DAILY", kind: .daily)
                    Rectangle().fill(Theme.ndBorderVisible.resolve(for: colorScheme)).frame(width: 1)
                    cadenceButton(label: "WEEKDAYS", kind: .weekdays)
                }
                .frame(height: 44)
                Rectangle().fill(Theme.ndBorderVisible.resolve(for: colorScheme)).frame(height: 1)
                HStack(spacing: 0) {
                    cadenceButton(label: "X / DAY", kind: .perDay)
                    Rectangle().fill(Theme.ndBorderVisible.resolve(for: colorScheme)).frame(width: 1)
                    cadenceButton(label: "X / WEEK", kind: .perWeek)
                }
                .frame(height: 44)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

            if cadenceKind == .perDay || cadenceKind == .perWeek {
                cadenceStepper
            }
        }
    }

    private func cadenceButton(label: String, kind: CadenceKind) -> some View {
        let isActive = cadenceKind == kind
        return Button {
            withAnimation(.easeOut(duration: Theme.microDuration)) {
                switch kind {
                case .daily: cadence = .daily
                case .weekdays: cadence = .weekdays
                case .perDay: cadence = .timesPerDay(perDayN)
                case .perWeek: cadence = .timesPerWeek(perWeekN)
                }
            }
            Theme.lightHaptic()
        } label: {
            Text(label)
                .font(Theme.labelFont(size: Theme.labelSize))
                .tracking(Theme.labelSize * 0.04)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(
                    isActive
                        ? Theme.ndBlack.resolve(for: colorScheme)
                        : Theme.ndTextSecondary.resolve(for: colorScheme)
                )
                .background(isActive ? Theme.ndTextDisplay.resolve(for: colorScheme) : .clear)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cadenceStepper: some View {
        let isPerDay = cadenceKind == .perDay
        let n = isPerDay ? perDayN : perWeekN
        let lower = 2
        let upper = isPerDay ? 12 : 6
        let unit = isPerDay ? "times per day" : "times per week"

        HStack(spacing: Theme.spaceMD) {
            stepButton(system: "minus", enabled: n > lower) {
                setCadenceCount(n - 1, isPerDay: isPerDay)
            }
            Text("\(n)")
                .font(Theme.headingFont(size: 22))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                .frame(minWidth: 28)
                .contentTransition(.numericText())
            stepButton(system: "plus", enabled: n < upper) {
                setCadenceCount(n + 1, isPerDay: isPerDay)
            }
            Text(unit)
                .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
            Spacer()
        }
        .padding(.top, Theme.spaceSM)
    }

    private func stepButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled else { return }
            withAnimation(.easeOut(duration: Theme.microDuration)) { action() }
            Theme.lightHaptic()
        } label: {
            Image(systemName: system)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    enabled
                        ? Theme.ndTextPrimary.resolve(for: colorScheme)
                        : Theme.ndTextDisabled.resolve(for: colorScheme)
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Circle().strokeBorder(
                        (enabled ? Theme.ndBorderVisible : Theme.ndBorder).resolve(for: colorScheme),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func setCadenceCount(_ value: Int, isPerDay: Bool) {
        let clamped = max(2, min(isPerDay ? 12 : 6, value))
        cadence = isPerDay ? .timesPerDay(clamped) : .timesPerWeek(clamped)
    }
}

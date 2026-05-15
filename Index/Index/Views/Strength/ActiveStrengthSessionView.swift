import SwiftUI
import SwiftData
import UIKit
import Combine

/// Active strength workout — freestyle (no templates in v2). Top bar shows
/// the elapsed clock + End button; the body presents the current exercise
/// with weight/reps inputs, quick-adjust chips, and a Complete-Set primary
/// button. The bottom action lets the user switch exercises mid-session.
///
/// On end:
///   - If no sets were logged, the StrengthSession is discarded (deleted)
///     so empty taps don't pollute the feed.
///   - Otherwise the StrengthSession's endDate is stamped and a parallel
///     WorkoutSession(type: .strength, strengthSessionId: session.id) is
///     inserted so the cross-module Fitness surfaces pick it up.
struct ActiveStrengthSessionView: View {
    var seedExercise: UserExercise?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Audit H17 — bounded to last 365 days. The view uses
    /// `allSessions` only to seed inputs from the user's last logged
    /// set per exercise (`lastSessionPerformance`); a year of training
    /// history is far more than enough for that lookup, and the bound
    /// stops SwiftData from transitively pulling every SetEntry ever
    /// logged through the cascade chain.
    @Query private var allSessions: [StrengthSession]
    /// UserExercise library is intentionally tiny (max 10 starter
    /// catalog items, soft-hide via DQ4) — left unbounded.
    @Query(sort: \UserExercise.displayOrder) private var userExercises: [UserExercise]

    init(seedExercise: UserExercise? = nil) {
        self.seedExercise = seedExercise
        let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: .now) ?? .distantPast
        _allSessions = Query(
            filter: #Predicate<StrengthSession> { $0.date > cutoff },
            sort: \StrengthSession.date,
            order: .reverse
        )
    }

    @State private var session: StrengthSession? = nil
    @State private var currentExercise: UserExercise? = nil
    @State private var currentPerformance: ExercisePerformance? = nil

    @State private var startedAt: Date = .now
    @State private var tickNow: Date = .now

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @FocusState private var focusedField: Field?

    @State private var showExercisePicker = false
    @State private var showEndConfirm = false
    @State private var showRest = false
    @State private var restSeconds = 90

    private enum Field: Hashable { case weight, reps }

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var elapsedSec: Int {
        max(0, Int(tickNow.timeIntervalSince(startedAt)))
    }

    private var thisSessionSets: [(performance: ExercisePerformance, set: SetEntry)] {
        guard let s = session else { return [] }
        var out: [(ExercisePerformance, SetEntry)] = []
        for perf in s.orderedPerformances {
            for set in perf.orderedSets {
                out.append((perf, set))
            }
        }
        return out.sorted { $0.1.completedAt < $1.1.completedAt }
    }

    private var canCompleteSet: Bool {
        guard currentExercise != nil,
              let r = Int(repsText), r > 0 else { return false }
        let w = Double(weightText.replacingOccurrences(of: ",", with: "."))
        // weight can be 0 for pure-bodyweight sets
        return (w ?? 0) >= 0
    }

    private func lastSessionPerformance(for exerciseId: String) -> ExercisePerformance? {
        let currentSessionId = session?.persistentModelID
        for s in allSessions where s.persistentModelID != currentSessionId {
            if let perf = (s.performances ?? []).first(where: {
                $0.userExerciseId == exerciseId && !($0.sets ?? []).isEmpty
            }) {
                return perf
            }
        }
        return nil
    }

    var body: some View {
        // Audit H18 — derive once per body. The 1Hz timer drives a
        // body re-eval every second; without the cache, thisSessionSets
        // re-walked + re-sorted every set in the current session 3×
        // per second (used by emptiness check, ForEach, and the alert
        // message). One call now feeds all three sites.
        let setsThisSession = thisSessionSets
        return NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if let ex = currentExercise {
                                currentExerciseCard(ex)
                            } else {
                                pickPrompt
                            }
                            Divider()
                            thisSessionSection(sets: setsThisSession)
                        }
                        .padding()
                    }
                    bottomActions
                }

                if showRest {
                    RestTimerOverlay(isShowing: $showRest, durationSeconds: restSeconds)
                        .zIndex(10)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear(perform: setupOnAppear)
        .onReceive(timer) { now in tickNow = now }
        .onChange(of: currentExercise) { _, newValue in
            guard let ex = newValue else { return }
            seedInputs(from: ex)
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet { picked in
                showExercisePicker = false
                switchToExercise(picked)
            }
        }
        .alert("End session?", isPresented: $showEndConfirm) {
            Button("Keep going", role: .cancel) {}
            Button("End", role: .destructive) { endSession() }
        } message: {
            Text(setsThisSession.isEmpty
                 ? "No sets logged — the session will be discarded."
                 : "Saves the session and adds it to today's workouts.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("STRENGTH · \(formatStart(startedAt))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                Text(formatElapsed(elapsedSec))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Button("End") { showEndConfirm = true }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Pick prompt

    private var pickPrompt: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: "plus.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Pick an exercise to start")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Add exercise") { showExercisePicker = true }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Current exercise

    private func currentExerciseCard(_ ex: UserExercise) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ex.name)
                .font(.title.weight(.semibold))

            Text(lastSummary(for: ex.id))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .tracking(1)

            HStack(spacing: 14) {
                weightField(for: ex)
                repsField
            }

            VStack(alignment: .leading, spacing: 8) {
                quickRow(label: weightFieldLabel(for: ex), chips: [-2.5, -1.25, 1.25, 2.5], isWeight: true)
                quickRow(label: "REPS", chips: [-1, 1], isWeight: false)
            }

            Button(action: completeSet) {
                Text("Complete set")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canCompleteSet)
        }
    }

    private func weightField(for ex: UserExercise) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weightFieldLabel(for: ex))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("0", text: $weightText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .focused($focusedField, equals: .weight)
                Text("KG")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) { Divider() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var repsField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REPS")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("0", text: $repsText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .focused($focusedField, equals: .reps)
                Text("×")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) { Divider() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickRow(label: String, chips: [Double], isWeight: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .tracking(1.5)
                .frame(width: 70, alignment: .leading)
            ForEach(chips, id: \.self) { delta in
                Button(formatDelta(delta, isWeight: isWeight)) {
                    if isWeight { bumpWeight(delta) } else { bumpReps(Int(delta)) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
    }

    private func formatDelta(_ d: Double, isWeight: Bool) -> String {
        if isWeight {
            let sign = d > 0 ? "+" : "−"
            let mag = abs(d)
            let s = mag == floor(mag) ? "\(Int(mag))" : String(format: "%.2f", mag)
            return "\(sign)\(s)"
        }
        return d > 0 ? "+\(Int(d))" : "−\(Int(abs(d)))"
    }

    // MARK: - This session

    private func thisSessionSection(sets: [(performance: ExercisePerformance, set: SetEntry)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This session")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            if sets.isEmpty {
                Text("No sets logged yet.")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .tracking(1)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sets.enumerated()), id: \.offset) { idx, item in
                        sessionSetRow(idx: idx, item: item)
                        if idx < sets.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private func sessionSetRow(idx: Int, item: (performance: ExercisePerformance, set: SetEntry)) -> some View {
        let name = userExercises.first(where: { $0.id == item.performance.userExerciseId })?.name ?? "—"
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return HStack {
            Text("Set \(idx + 1)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatKg(item.set.weightKg)) kg × \(item.set.reps)")
                    .font(.body.monospacedDigit())
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(f.string(from: item.set.completedAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Setup / lifecycle

    private func setupOnAppear() {
        // Idempotent: if a session was already inserted (e.g. SwiftUI
        // re-fired .onAppear after a sheet dismiss), don't insert
        // another. Prevents the audit-flagged regression where a
        // re-appear leaks an empty StrengthSession row.
        guard session == nil else { return }
        startedAt = .now
        tickNow = .now
        let s = StrengthSession(
            date: startedAt,
            endDate: startedAt,
            notes: "",
            inProgress: true
        )
        context.insert(s)
        session = s
        if let seed = seedExercise {
            switchToExercise(seed)
        }
    }

    private func switchToExercise(_ ex: UserExercise) {
        currentExercise = ex
        currentPerformance = nil
        seedInputs(from: ex)
    }

    private func performanceOrCreate(_ ex: UserExercise) -> ExercisePerformance {
        if let existing = currentPerformance, existing.userExerciseId == ex.id {
            return existing
        }
        if let s = session,
           let existing = (s.performances ?? []).first(where: { $0.userExerciseId == ex.id }) {
            currentPerformance = existing
            return existing
        }
        let nextOrder = ((session?.performances ?? []).map(\.order).max() ?? -1) + 1
        let perf = ExercisePerformance(
            session: session,
            userExerciseId: ex.id,
            order: nextOrder
        )
        context.insert(perf)
        currentPerformance = perf
        return perf
    }

    /// Seeds the inputs from the user's most recent SetEntry for this
    /// exercise, across all sessions. Empty fields when no history exists.
    private func seedInputs(from ex: UserExercise) {
        for s in allSessions {
            for perf in (s.performances ?? []) where perf.userExerciseId == ex.id {
                if let last = perf.orderedSets.last {
                    weightText = formatKg(last.weightKg)
                    repsText = "\(last.reps)"
                    return
                }
            }
        }
        weightText = ""
        repsText = ""
    }

    // MARK: - Complete set / End

    private func completeSet() {
        guard canCompleteSet,
              let ex = currentExercise,
              let r = Int(repsText),
              let s = session else { return }
        let w = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0

        let perf = performanceOrCreate(ex)
        let nextOrder = (perf.sets ?? []).count
        let set = SetEntry(
            performance: perf,
            order: nextOrder,
            weightKg: w,
            reps: r,
            completedAt: .now
        )
        context.insert(set)
        perf.sets = (perf.sets ?? []) + [set]
        s.endDate = .now

        let g = UIImpactFeedbackGenerator(style: .medium)
        g.impactOccurred()

        restSeconds = ex.defaultRestSeconds
        withAnimation(.easeOut(duration: 0.18)) { showRest = true }
    }

    private func endSession() {
        guard let s = session else { dismiss(); return }
        if !thisSessionSets.isEmpty {
            s.endDate = .now
            s.inProgress = false  // Audit H16 — explicit flag flip.
            // Insert parallel WorkoutSession so the Fitness feed,
            // Brain insights, and any cross-module surface pick it up.
            let workout = WorkoutSession(
                date: s.date,
                type: .strength,
                durationMinutes: max(1, s.durationMinutes),
                source: .manual,
                strengthSessionId: s.id
            )
            context.insert(workout)
        } else {
            context.delete(s)
        }
        dismiss()
    }

    // MARK: - Helpers

    private func bumpWeight(_ delta: Double) {
        let current = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let next = max(0, current + delta)
        weightText = formatKg(next)
    }

    private func bumpReps(_ delta: Int) {
        let current = Int(repsText) ?? 0
        let next = max(0, current + delta)
        repsText = "\(next)"
    }

    private func weightFieldLabel(for ex: UserExercise) -> String {
        switch ex.kind {
        case .bodyweight: "ADDED"
        case .assisted:   "ASSIST"
        case .free, .machine: "WEIGHT"
        }
    }

    private func lastSummary(for exerciseId: String) -> String {
        guard let perf = lastSessionPerformance(for: exerciseId),
              !perf.orderedSets.isEmpty else { return "FIRST TIME" }
        let parts = perf.orderedSets.prefix(5).map { "\(formatKg($0.weightKg)) × \($0.reps)" }
        return "LAST: " + parts.joined(separator: ", ")
    }

    private func formatStart(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func formatElapsed(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func formatKg(_ kg: Double) -> String {
        SafeFormat.decimal(kg)
    }
}

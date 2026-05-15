import SwiftUI
import SwiftData

/// Phase 7 — Settings. Reachable via the gear icon in the top-right of
/// every main tab (BodyView, FitnessMainView, NutritionMainView).
/// Presented as a `.sheet` (NOT `.fullScreenCover`) so the dismiss
/// gesture works automatically and the chrome feels lighter.
///
/// Design language: tinted via `IndexPalette.Module.settings` (French
/// Blue, same as Body) — used for active toggle states, selected
/// segments, primary action buttons, and chevron tint on tappable rows.
/// The X dismiss button in the toolbar explicitly overrides
/// `foregroundStyle` to `IndexPalette.Text.secondary` so it doesn't
/// inherit the tint cascade.
///
/// All field edits open a sub-sheet (single field per sheet) that
/// validates via `FieldValidation` and saves through a
/// `ProfileService.update*` method (audit transactional-save
/// discipline). Save failures surface as a non-blocking banner here
/// rather than throwing modally.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileService.self) private var profileService
    @Environment(HealthKitService.self) private var hkService
    @Environment(NotificationService.self) private var notificationService

    // Sheet routing state — one item per editable field. Single
    // optional binding instead of one Bool per sheet so SwiftUI never
    // tries to present two simultaneously.
    @State private var activeSheet: SheetRoute? = nil
    @State private var saveErrorMessage: String? = nil
    @State private var infoBannerMessage: String? = nil

    // Phase 7c — destructive-action confirmations
    @State private var showExportStub = false
    @State private var showResetConfirm = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var showNotificationDeniedAlert = false

    enum SheetRoute: String, Identifiable {
        case name, age, height, sex
        case direction, calorieAdjustment, proteinTarget, targetWeight
        case healthStatus
        var id: String { rawValue }
    }

    private var profile: Profile? { profileService.activeProfile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let msg = saveErrorMessage {
                        saveErrorBanner(msg)
                    }
                    if let msg = infoBannerMessage {
                        infoBanner(msg)
                    }
                    if profile != nil {
                        profileSection
                        goalSection
                        modulesSection
                        manualLoggingSection
                        strengthSection
                        appleHealthSection
                        notificationsSection
                        dataSection
                        accountSection
                    } else {
                        // Defensive: shouldn't reach Settings without an
                        // active profile, but if somehow we do, render
                        // a minimal explanation rather than crashing.
                        Text("No active profile.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    aboutSection
                    swissFooter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(IndexPalette.Text.secondary)
                    }
                }
            }
            .sheet(item: $activeSheet) { route in
                editSheet(for: route)
            }
        }
        .tint(IndexPalette.Module.settings)
    }

    // MARK: - Save error banner

    private func saveErrorBanner(_ msg: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(IndexPalette.Semantic.warning)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button("Dismiss") { saveErrorMessage = nil }
                .font(.caption.weight(.semibold))
        }
        .padding()
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func infoBanner(_ msg: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(IndexPalette.Semantic.success)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button("Dismiss") { infoBannerMessage = nil }
                .font(.caption.weight(.semibold))
        }
        .padding()
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Profile

    private var profileSection: some View {
        section(caption: "Profile") {
            row(label: "Name", value: profile?.name ?? "—") {
                activeSheet = .name
            }
            divider
            row(label: "Age", value: profile.map { "\($0.age)" } ?? "—") {
                activeSheet = .age
            }
            divider
            row(label: "Height", value: profile.map { "\(Int($0.heightCm.rounded())) cm" } ?? "—") {
                activeSheet = .height
            }
            divider
            row(label: "Sex", value: profile?.sex.label ?? "—") {
                activeSheet = .sex
            }
        }
    }

    // MARK: - Goal

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCaption("Goal")
            VStack(spacing: 0) {
                row(label: "Direction", value: profile.map { directionLabel($0.goal) } ?? "—") {
                    activeSheet = .direction
                }
                divider
                row(
                    label: "Calorie adjustment",
                    value: profile.map { calorieAdjustmentLabel($0.calorieAdjustmentKcal) } ?? "—"
                ) {
                    activeSheet = .calorieAdjustment
                }
                divider
                row(label: "Protein target", value: profile.map { "\(Int($0.proteinTargetG.rounded())) g/day" } ?? "—") {
                    activeSheet = .proteinTarget
                }
                divider
                row(label: "Target weight", value: profile.map { targetWeightLabel($0) } ?? "—") {
                    activeSheet = .targetWeight
                }
                divider
                eatBackToggleRow
            }
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
            Text("When off, your daily target ignores calories burned during workouts. Recommended for cutting.")
                .font(.caption2)
                .foregroundStyle(IndexPalette.Text.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var eatBackToggleRow: some View {
        let bound = Binding<Bool>(
            get: { profile?.eatBackWorkoutCalories ?? false },
            set: { isOn in
                do {
                    try profileService.setEatBackWorkoutCalories(isOn, in: context)
                } catch {
                    saveErrorMessage = "Couldn't update setting. Try again."
                }
            }
        )
        return HStack {
            Text("Eat back workout calories")
                .font(IndexFont.rowTitle)
                .foregroundStyle(IndexPalette.Text.primary)
            Spacer()
            Toggle("", isOn: bound)
                .labelsHidden()
                .tint(IndexPalette.Module.settings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func directionLabel(_ g: Goal) -> String {
        switch g {
        case .lose:     "Cutting"
        case .maintain: "Maintaining"
        case .gain:     "Bulking"
        }
    }

    private func calorieAdjustmentLabel(_ kcal: Double) -> String {
        let i = Int(kcal.rounded())
        if i == 0 { return "0 kcal/day" }
        let sign = i > 0 ? "+" : ""
        return "\(sign)\(i) kcal/day"
    }

    private func targetWeightLabel(_ p: Profile) -> String {
        guard p.hasTargetWeight else { return "Not set" }
        return "\(SafeFormat.decimal(p.targetWeightKg)) kg"
    }

    // MARK: - Modules

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCaption("Modules")
            VStack(spacing: 0) {
                moduleToggleRow(.body, alwaysOn: true)
                divider
                moduleToggleRow(.fitness)
                divider
                moduleToggleRow(.nutrition)
            }
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
            Text("Turning off a module hides it but keeps your data.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func moduleToggleRow(_ module: Module, alwaysOn: Bool = false) -> some View {
        let bound = Binding<Bool>(
            get: { profile?.enabledModules.contains(module) ?? false },
            set: { isOn in
                guard !alwaysOn else { return }
                do {
                    try profileService.setModuleEnabled(module, enabled: isOn, in: context)
                } catch {
                    saveErrorMessage = "Couldn't update module. Try again."
                }
            }
        )
        return HStack {
            Text(module.label)
                .font(IndexFont.rowTitle)
            Spacer()
            Toggle("", isOn: bound)
                .labelsHidden()
                .disabled(alwaysOn)
                .tint(IndexPalette.Module.settings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Manual logging
    //
    // Two toggles that gate the "Log" toolbar button in BodyView /
    // FitnessMainView. Both default off — automated sources (Apple
    // Health from RENPHO for weight, Apple Watch for workouts) are
    // assumed to be the primary write path. HealthKit auto-imports
    // and tap-to-edit on past entries are unaffected.

    private var manualLoggingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCaption("Manual logging")
            VStack(spacing: 0) {
                manualLoggingRow(
                    label: "Weight",
                    isOn: Binding(
                        get: { profile?.manualWeightLoggingEnabled ?? false },
                        set: { isOn in
                            do {
                                try profileService.setManualWeightLoggingEnabled(isOn, in: context)
                            } catch {
                                saveErrorMessage = "Couldn't update setting. Try again."
                            }
                        }
                    )
                )
                divider
                manualLoggingRow(
                    label: "Fitness",
                    isOn: Binding(
                        get: { profile?.manualFitnessLoggingEnabled ?? false },
                        set: { isOn in
                            do {
                                try profileService.setManualFitnessLoggingEnabled(isOn, in: context)
                            } catch {
                                saveErrorMessage = "Couldn't update setting. Try again."
                            }
                        }
                    )
                )
            }
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
            Text("When off, the Log button is hidden. HealthKit auto-imports continue regardless.")
                .font(.caption2)
                .foregroundStyle(IndexPalette.Text.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func manualLoggingRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(IndexFont.rowTitle)
                .foregroundStyle(IndexPalette.Text.primary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(IndexPalette.Module.settings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Strength exercises

    private var strengthSection: some View {
        section(caption: "Strength exercises") {
            NavigationLink {
                StrengthLibraryView()
            } label: {
                HStack {
                    Text("My exercises")
                        .font(IndexFont.rowTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(strengthCountLabel)
                        .font(IndexFont.rowValue)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IndexPalette.Text.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @Query(
        filter: #Predicate<UserExercise> { !$0.hiddenFromLibrary },
        sort: \UserExercise.displayOrder
    )
    private var visibleExercises: [UserExercise]

    private var strengthCountLabel: String {
        "\(visibleExercises.count) of \(ExerciseCatalog.starter.count) added"
    }

    // MARK: - Apple Health

    @State private var hkToggleTick: Int = 0  // forces toggle-state refresh after toggle change

    private var appleHealthSection: some View {
        section(caption: "Apple Health") {
            if hkService.isAuthorized {
                hkToggleRow(label: "Sync workouts", binding: workoutToggleBinding)
                divider
                hkToggleRow(label: "Sync weight", binding: weightToggleBinding)
                divider
            }
            row(label: "Status", value: hkStatusLabel) {
                activeSheet = .healthStatus
            }
        }
        .id(hkToggleTick)  // re-render after a toggle write
    }

    private func hkToggleRow(label: String, binding: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(IndexFont.rowTitle)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(IndexPalette.Module.settings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Notifications
    //
    // Local notifications fire from HealthKitService observer paths
    // on genuinely-new HK inserts (manual logs don't fire). Flipping
    // a toggle ON requests iOS permission via NotificationService;
    // on denial we surface a single alert directing the user to iOS
    // Settings. The toggle stays off until iOS permission is granted.

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCaption("Notifications")
            VStack(spacing: 0) {
                notificationToggleRow(
                    label: "New workouts",
                    isOn: notifyWorkoutBinding
                )
                divider
                notificationToggleRow(
                    label: "New weigh-ins",
                    isOn: notifyWeightBinding
                )
            }
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
            Text("Get notified when Apple Health imports a workout or weigh-in. Manual logs don't trigger notifications.")
                .font(.caption2)
                .foregroundStyle(IndexPalette.Text.secondary)
                .padding(.horizontal, 4)
        }
        .alert("Notifications are disabled", isPresented: $showNotificationDeniedAlert) {
            Button("OK") {}
        } message: {
            Text("Enable them under Settings → Notifications → Index.")
        }
    }

    private func notificationToggleRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(IndexFont.rowTitle)
                .foregroundStyle(IndexPalette.Text.primary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(IndexPalette.Module.settings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Binding that triggers the async permission flow on flip-ON.
    /// `get` reads the persisted profile flag; `set` kicks off a Task
    /// that calls `ProfileService.setNotifyOnNewWorkout` — that method
    /// internally requests iOS permission, throws on denial, and only
    /// saves the flag if permission is granted. On denial we surface
    /// the one-time alert and leave the toggle in its previous state.
    private var notifyWorkoutBinding: Binding<Bool> {
        Binding(
            get: { profile?.notifyOnNewWorkout ?? false },
            set: { isOn in
                Task {
                    do {
                        try await profileService.setNotifyOnNewWorkout(
                            isOn,
                            notificationService: notificationService,
                            in: context
                        )
                    } catch NotificationService.PermissionError.denied {
                        showNotificationDeniedAlert = true
                    } catch {
                        saveErrorMessage = "Couldn't update setting. Try again."
                    }
                }
            }
        )
    }

    private var notifyWeightBinding: Binding<Bool> {
        Binding(
            get: { profile?.notifyOnNewWeight ?? false },
            set: { isOn in
                Task {
                    do {
                        try await profileService.setNotifyOnNewWeight(
                            isOn,
                            notificationService: notificationService,
                            in: context
                        )
                    } catch NotificationService.PermissionError.denied {
                        showNotificationDeniedAlert = true
                    } catch {
                        saveErrorMessage = "Couldn't update setting. Try again."
                    }
                }
            }
        )
    }

    private var workoutToggleBinding: Binding<Bool> {
        Binding(
            get: { HealthKitService.workoutImportEnabled },
            set: { isOn in
                UserDefaults.standard.set(isOn, forKey: HealthKitService.importWorkoutsKey)
                if isOn {
                    hkService.startObservingWorkouts()
                } else {
                    hkService.stopWorkoutObserver()
                }
                hkToggleTick += 1
            }
        )
    }

    private var weightToggleBinding: Binding<Bool> {
        Binding(
            get: { HealthKitService.weightImportEnabled },
            set: { isOn in
                UserDefaults.standard.set(isOn, forKey: HealthKitService.importWeightKey)
                if isOn {
                    hkService.startObservingBodyMass()
                } else {
                    hkService.stopBodyMassObserver()
                }
                hkToggleTick += 1
            }
        )
    }

    private var hkStatusLabel: String {
        hkService.isAuthorized ? "Connected" : "Not connected"
    }

    // MARK: - Data

    private var dataSection: some View {
        section(caption: "Data") {
            row(label: "Export data", value: nil) {
                showExportStub = true
            }
            divider
            destructiveRow(label: "Reset all data") {
                showResetConfirm = true
            }
        }
        .alert("Export coming soon", isPresented: $showExportStub) {
            Button("OK") {}
        } message: {
            Text("Data export is on the roadmap for a future update.")
        }
        .confirmationDialog(
            "Reset all data?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive, action: performReset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all logged weights, workouts, meals, and exercise sessions. Your profile and exercise library will remain. This cannot be undone.")
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        section(caption: "Account") {
            destructiveRow(label: "Sign out") {
                showSignOutConfirm = true
            }
            divider
            destructiveRow(label: "Delete account") {
                showDeleteAccountConfirm = true
            }
        }
        .confirmationDialog(
            "Sign out?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive, action: performSignOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be signed out. Your local data stays on this device.")
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: performDeleteAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes your profile and all data. This cannot be undone.")
        }
    }

    // MARK: - Destructive action handlers

    private func performReset() {
        do {
            try profileService.resetAllData(in: context)
            infoBannerMessage = "Data reset. Your profile and exercise library were preserved."
        } catch {
            saveErrorMessage = "Couldn't reset data. Try again."
        }
    }

    private func performSignOut() {
        Task {
            await profileService.signOut()
            // ContentView observes activeProfile == nil and routes to
            // OnboardingView automatically; dismissing the sheet
            // surfaces that transition.
            dismiss()
        }
    }

    private func performDeleteAccount() {
        Task {
            do {
                try await profileService.deleteAccount(in: context)
                dismiss()
            } catch {
                saveErrorMessage = "Couldn't delete account. Try again."
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        section(caption: "About") {
            staticRow(label: "Version", value: aboutVersion)
            divider
            staticRow(label: "Build date", value: aboutBuildDate)
        }
    }

    private var aboutVersion: String {
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
        let b = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
        return "\(v) (\(b))"
    }

    private var aboutBuildDate: String {
        // Build date approximated from the executable's modification
        // date — close enough for an "about" surface, and avoids a
        // build-script dance to inject a literal at compile time.
        if let path = Bundle.main.executablePath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let date = attrs[.modificationDate] as? Date {
            let f = DateFormatter()
            f.dateFormat = "MMM d, yyyy"
            return f.string(from: date)
        }
        return "—"
    }

    private var swissFooter: some View {
        Text("Made with care in Switzerland")
            .font(.caption2.italic())
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    // MARK: - Section + row helpers

    private func section<Content: View>(
        caption: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCaption(caption)
            VStack(spacing: 0) { content() }
                .background(IndexPalette.Surface.card)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func sectionCaption(_ text: String) -> some View {
        // Callers pass mixed-case ("Goal", "Manual logging") which
        // this helper renders uppercase via the literal — no
        // .textCase modifier, so SwiftUI doesn't double-uppercase
        // when the source string is already upper.
        Text(text.uppercased())
            .font(IndexFont.sectionCap)
            .kerning(0.8)
            .foregroundStyle(IndexPalette.Text.tertiary)
            .padding(.horizontal, 4)
    }

    private var divider: some View {
        Divider().padding(.leading, 14)
    }

    private func row(label: String, value: String?, action: @escaping () -> Void) -> some View {
        // Value text uses `IndexFont.rowValue` (17pt + monospacedDigit).
        // monospacedDigit is a no-op on non-digit characters, so the
        // same helper handles "188 cm", "+500 kcal/day", and pure-text
        // values like "Yannis" / "Cutting" without a switch.
        Button(action: action) {
            HStack {
                Text(label)
                    .font(IndexFont.rowTitle)
                    .foregroundStyle(IndexPalette.Text.primary)
                Spacer()
                if let value {
                    Text(value)
                        .font(IndexFont.rowValue)
                        .foregroundStyle(IndexPalette.Text.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IndexPalette.Text.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func staticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(IndexFont.rowTitle)
                .foregroundStyle(IndexPalette.Text.primary)
            Spacer()
            Text(value)
                .font(IndexFont.rowValue)
                .foregroundStyle(IndexPalette.Text.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func destructiveRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(IndexFont.rowTitle)
                    .foregroundStyle(IndexPalette.Action.destructive)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Edit sheet routing

    @ViewBuilder
    private func editSheet(for route: SheetRoute) -> some View {
        switch route {
        case .name:               NameEditSheet(onError: surfaceError)
        case .age:                AgeEditSheet(onError: surfaceError)
        case .height:             HeightEditSheet(onError: surfaceError)
        case .sex:                SexEditSheet(onError: surfaceError)
        case .direction:          DirectionEditSheet(onError: surfaceError)
        case .calorieAdjustment:  CalorieAdjustmentEditSheet(onError: surfaceError)
        case .proteinTarget:      ProteinTargetEditSheet(onError: surfaceError)
        case .targetWeight:       TargetWeightEditSheet(onError: surfaceError)
        case .healthStatus:       HealthStatusSheet()
        }
    }

    private func surfaceError(_ message: String) {
        saveErrorMessage = message
    }
}

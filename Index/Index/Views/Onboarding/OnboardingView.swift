import SwiftUI

/// Working state collected across the 8 onboarding steps. Held as @State on
/// OnboardingView until the user finishes; the completion callback receives
/// the populated draft. P3.11 wires that callback to ProfileService so the
/// draft becomes a persisted Profile.
struct OnboardingDraft: Equatable {
    var userId: String = ""
    var name: String = ""
    var age: Int = 30
    var heightCm: Double = 175
    var sex: Sex = .male
    var activityLevel: ActivityLevel = .moderatelyActive
    var goal: Goal = .maintain
    var targetWeightKg: Double = 0
    var hasTargetWeight: Bool = false
    var enabledModules: Set<Module> = [.body, .fitness, .nutrition]
    var selectedExerciseIds: Set<String> = []
    var appleHealthAuthorized: Bool = false
}

/// 8-step onboarding flow. System default styling — visual pass lands later
/// as a separate prompt.
///
/// Step navigation is linear (Back / Continue) with one branch: when the
/// Fitness module is toggled off in step 6, step 7 (exercise picker) is
/// skipped on both forward and back navigation.
struct OnboardingView: View {
    let identity: any IdentityService
    let onComplete: (OnboardingDraft) -> Void

    @State private var step: Int = 1
    @State private var draft = OnboardingDraft()
    @State private var signInError: String? = nil
    @State private var signingIn = false

    private var totalVisibleSteps: Int {
        draft.enabledModules.contains(.fitness) ? 8 : 7
    }

    /// What "Step N" the user sees — accounts for skipping step 7 when
    /// Fitness is off.
    private var visibleStepNumber: Int {
        if step > 7, !draft.enabledModules.contains(.fitness) { return step - 1 }
        return step
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView { stepContent.padding(.horizontal) }
                .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                if canGoBack {
                    Button("Back", action: goBack)
                } else {
                    Color.clear.frame(width: 60)
                }
                Spacer()
                Text("Step \(visibleStepNumber) of \(totalVisibleSteps)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 60)
            }
            ProgressView(value: Double(visibleStepNumber), total: Double(totalVisibleSteps))
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if step == 1, let signInError {
                Text(signInError).font(.caption).foregroundStyle(.red)
            }
            Button(action: handlePrimary) {
                Text(primaryLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!primaryEnabled)

            if step == 8 {
                Button("Skip for now") { complete() }
                    .buttonStyle(.borderless)
            }
        }
        .padding()
    }

    private var primaryLabel: String {
        switch step {
        case 1: signingIn ? "Signing in…" : "Get started"
        case 8: "Connect Apple Health"
        default: visibleStepNumber == totalVisibleSteps ? "Open Index" : "Continue"
        }
    }

    private var primaryEnabled: Bool {
        switch step {
        case 1: !signingIn
        case 3: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        default: true
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 1: signInStep
        case 2: welcomeStep
        case 3: profileBasicsStep
        case 4: activityLevelStep
        case 5: goalStep
        case 6: moduleSelectionStep
        case 7: exercisePickerStep
        case 8: healthConnectStep
        default: EmptyView()
        }
    }

    // 1 — Sign in.
    // FUTURE: when AppleSignInIdentityService is wired in post-enrollment,
    // replace this view with SignInWithAppleButton (AuthenticationServices)
    // and tighten primaryLabel/handlePrimary to delegate the OAuth flow to
    // it. The underlying signIn() async-returns the userId either way, so
    // the rest of this view doesn't need to change.
    private var signInStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Welcome to Index.")
            Text("Your body, fitness, and nutrition — interpreted, not just displayed.")
                .foregroundStyle(.secondary)
            Spacer(minLength: 40)
        }
        .padding(.top, 24)
    }

    // 2 — Welcome.
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("How it works.")
            Text("Three modules — Body, Fitness, Nutrition — each with a Brain that reads across them.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                bullet("Apple Watch workouts auto-import.")
                bullet("Weight, body fat, and lean mass from your scale via Apple Health.")
                bullet("A short insight per module — no dashboards to scroll.")
            }
            .padding(.top, 8)
        }
        .padding(.top, 24)
    }

    // 3 — Profile basics.
    private var profileBasicsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Tell us about you.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Your name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Age").font(.caption).foregroundStyle(.secondary)
                    Stepper(value: $draft.age, in: 13...110) {
                        Text("\(draft.age)")
                            .monospacedDigit()
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Height (cm)").font(.caption).foregroundStyle(.secondary)
                    TextField("175", value: $draft.heightCm, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Sex").font(.caption).foregroundStyle(.secondary)
                Picker("Sex", selection: $draft.sex) {
                    ForEach(Sex.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.top, 24)
    }

    // 4 — Activity level.
    private var activityLevelStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("How active are you?")
            Text("Used to estimate TDEE — the calories you burn in a typical day.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    optionRow(
                        selected: draft.activityLevel == level,
                        title: level.label,
                        subtitle: level.detail
                    ) {
                        draft.activityLevel = level
                    }
                }
            }
        }
        .padding(.top, 24)
    }

    // 5 — Goal.
    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("What's your goal?")
            VStack(spacing: 8) {
                ForEach(Goal.allCases, id: \.self) { g in
                    optionRow(
                        selected: draft.goal == g,
                        title: g.label,
                        subtitle: nil
                    ) {
                        draft.goal = g
                    }
                }
            }
            if draft.goal != .maintain {
                Divider().padding(.vertical, 8)
                Toggle("Set a target weight", isOn: $draft.hasTargetWeight)
                if draft.hasTargetWeight {
                    HStack {
                        Text("Target weight")
                        Spacer()
                        TextField(
                            "75",
                            value: $draft.targetWeightKg,
                            format: .number.precision(.fractionLength(1))
                        )
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        Text("kg").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.top, 24)
    }

    // 6 — Module selection.
    private var moduleSelectionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Which modules?")
            Text("Disabled modules are hidden from the tab bar. You can change this later in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(Module.allCases, id: \.self) { m in
                    moduleToggleRow(module: m)
                }
            }
        }
        .padding(.top, 24)
    }

    private func moduleToggleRow(module: Module) -> some View {
        Toggle(isOn: Binding(
            get: { draft.enabledModules.contains(module) },
            set: { isOn in
                if isOn { draft.enabledModules.insert(module) }
                else    { draft.enabledModules.remove(module) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(module.label)
                Text(module.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 10))
    }

    // 7 — Exercise picker (only if Fitness on; skipped via navigation).
    private var exercisePickerStep: some View {
        let count = draft.selectedExerciseIds.count
        return VStack(alignment: .leading, spacing: 16) {
            heading("Pick your exercises.")
            Text("Choose up to 5 from the starter catalog. You'll log sets against these.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Text("\(count) / 5 selected")
                    .font(.caption.monospaced())
                    .foregroundStyle(count == 5 ? Color.accentColor : .secondary)
            }
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(ExerciseCatalog.starter) { ex in
                    exerciseTile(ex)
                }
            }
        }
        .padding(.top, 24)
    }

    private func exerciseTile(_ ex: ExerciseDefinition) -> some View {
        let isSelected = draft.selectedExerciseIds.contains(ex.id)
        let isCapReached = draft.selectedExerciseIds.count >= 5 && !isSelected
        return Button {
            if isSelected {
                draft.selectedExerciseIds.remove(ex.id)
            } else if !isCapReached {
                draft.selectedExerciseIds.insert(ex.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(ex.name)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(ex.kind.caption)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 10))
            .opacity(isCapReached ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isCapReached)
    }

    // 8 — Apple Health connect (placeholder — actual HK auth lands in P3.12).
    private var healthConnectStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Connect Apple Health.")
            Text("Index reads weight, body composition, workouts, heart rate, HRV, VO2 max, and resting heart rate. It writes only manual weight entries back.")
                .foregroundStyle(.secondary)
            Text("You can change this anytime from Settings.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 24)
    }

    // MARK: - Reusable cells

    private func heading(_ s: String) -> some View {
        Text(s)
            .font(.title.weight(.semibold))
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(s)
        }
    }

    private func optionRow(
        selected: Bool,
        title: String,
        subtitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                selected
                    ? Color.accentColor.opacity(0.10)
                    : Color(.secondarySystemBackground)
            )
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private var canGoBack: Bool { step > 1 }

    private func goBack() {
        // Skip back over step 7 when Fitness is off.
        if step == 8, !draft.enabledModules.contains(.fitness) {
            step = 6
            return
        }
        step = max(1, step - 1)
    }

    /// Primary button on the footer. On step 1 it kicks off sign-in then
    /// advances on success. On step 8 it triggers the HK connect path
    /// (still a no-op in P3.10 — P3.12 fills it in). Otherwise it just
    /// advances.
    private func handlePrimary() {
        switch step {
        case 1:
            Task { await performSignIn() }
        case 8:
            // P3.10: placeholder — advance immediately. P3.12 wires the
            // real HK authorization request here.
            complete()
        default:
            advance()
        }
    }

    private func advance() {
        // Skip step 7 if Fitness is off.
        if step == 6, !draft.enabledModules.contains(.fitness) {
            step = 8
            return
        }
        if visibleStepNumber == totalVisibleSteps {
            complete()
            return
        }
        step += 1
    }

    private func complete() {
        onComplete(draft)
    }

    @MainActor
    private func performSignIn() async {
        signingIn = true
        signInError = nil
        defer { signingIn = false }
        do {
            let id = try await identity.signIn()
            draft.userId = id
            advance()
        } catch {
            signInError = "Sign-in failed. Try again."
        }
    }
}

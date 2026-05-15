import SwiftUI

/// Working state collected across the 8 onboarding steps. Held as @State on
/// OnboardingView until the user finishes; the completion callback receives
/// the populated draft.
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

/// Which TextField currently owns the keyboard. Auto-set on .onAppear of
/// the relevant step so the keyboard rises immediately on navigation
/// rather than on first tap (which has noticeable focus-resolution lag).
private enum OnboardingField: Hashable {
    case name
    case heightCm
    case targetWeight
}

/// 8-step onboarding flow. System default styling — visual pass lands later
/// as a separate prompt.
///
/// Layout pattern: chrome at top, step body fills middle vertical area
/// (`maxHeight: .infinity` on the ScrollView and `alignment: .leading` on
/// its content keep the form top-aligned), footer pinned at bottom.
struct OnboardingView: View {
    let identity: any IdentityService
    let onComplete: (OnboardingDraft) -> Void

    @Environment(HealthKitService.self) private var hkService

    @State private var step: Int = 1
    @State private var draft = OnboardingDraft()
    @State private var signInError: String? = nil
    @State private var signingIn = false
    @State private var connectingHealth = false
    @FocusState private var focusedField: OnboardingField?

    // Audit H13 — numeric validation ranges for the Continue gate.
    // Without these, a user could type 0 cm height or 0 kg target
    // and propagate the garbage into MetricsEngine downstream.
    private static let heightRangeCm:       ClosedRange<Double> = 100...250
    private static let targetWeightRangeKg: ClosedRange<Double> = 30...300

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
        VStack(alignment: .leading, spacing: 0) {
            chromeHeader

            // Step 7 needs scroll (10-tile grid); every other step fits the
            // viewport. Splitting keeps short steps top-aligned via a
            // trailing Spacer rather than relying on ScrollView's content
            // positioning, which centers in some iOS 26 layout contexts.
            if step == 7 {
                ScrollView {
                    stepContent
                        .padding(.horizontal)
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)
            } else {
                stepContent
                    .padding(.horizontal)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Chrome

    private var chromeHeader: some View {
        // ZStack so the Step counter sits in the absolute horizontal center
        // regardless of whether the Back button is present. The HStack
        // overlay supplies the Back button when canGoBack is true.
        //
        // The previous version used `Color.clear.frame(width: 60)` as a
        // placeholder to balance the Back button — but Color.clear is a
        // greedy view and the missing height constraint let the HStack
        // and the whole chromeHeader VStack stretch vertically, pushing
        // the form content into the middle/bottom of the screen.
        VStack(spacing: 10) {
            ZStack {
                Text("Step \(visibleStepNumber) of \(totalVisibleSteps)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack {
                    if canGoBack {
                        Button("Back", action: goBack)
                    }
                    Spacer()
                }
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
        case 8: connectingHealth ? "Requesting access…" : "Connect Apple Health"
        default: visibleStepNumber == totalVisibleSteps ? "Open Index" : "Continue"
        }
    }

    private var primaryEnabled: Bool {
        switch step {
        case 1: !signingIn
        case 3: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                && Self.heightRangeCm.contains(draft.heightCm)
        case 5:
            // Target-weight is optional unless `hasTargetWeight` is on;
            // if on, the value must fall in the sane range.
            !draft.hasTargetWeight
                || Self.targetWeightRangeKg.contains(draft.targetWeightKg)
        case 7:
            // DQ6: require at least one exercise when Fitness is on.
            // Step 7 is only reachable when Fitness is on (advance()
            // and goBack() skip it otherwise), so the count check
            // applies unconditionally here.
            draft.selectedExerciseIds.count >= 1
        case 8: !connectingHealth
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
        }
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
    }

    // 3 — Profile basics. Auto-focuses the Name field on appear so the
    // keyboard rises immediately rather than on first tap.
    private var profileBasicsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Tell us about you.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Your name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .heightCm }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Age").font(.caption).foregroundStyle(.secondary)
                    Stepper(value: $draft.age, in: 13...110) {
                        Text("\(draft.age)")
                            .monospacedDigit()
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height (cm)").font(.caption).foregroundStyle(.secondary)
                    TextField("175", value: $draft.heightCm, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .heightCm)
                    if !Self.heightRangeCm.contains(draft.heightCm) {
                        Text("Must be 100–250 cm")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
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
        .onAppear {
            // Race-free focus: SwiftUI needs a tick to install the
            // TextField before .focused() can attach. Hop through
            // MainActor.run so the focus assignment lands AFTER the
            // current render pass.
            Task { @MainActor in
                focusedField = .name
            }
        }
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
                    VStack(alignment: .leading, spacing: 4) {
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
                            .focused($focusedField, equals: .targetWeight)
                            Text("kg").foregroundStyle(.secondary)
                        }
                        if !Self.targetWeightRangeKg.contains(draft.targetWeightKg) {
                            Text("Must be 30–300 kg")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
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

    // 8 — Apple Health connect. Tapping the primary button requests HK
    // authorization; Skip bypasses it. Re-grantable from Settings later.
    private var healthConnectStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Connect Apple Health.")
            Text("Index reads weight, body composition, workouts, heart rate, HRV, VO2 max, and resting heart rate. It writes only manual weight entries back.")
                .foregroundStyle(.secondary)
            Text("You can change this anytime from Settings.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            if !HealthKitService.isAvailable {
                Label("Apple Health isn't available on this device.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
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
        focusedField = nil
        // Skip back over step 7 when Fitness is off.
        if step == 8, !draft.enabledModules.contains(.fitness) {
            step = 6
            return
        }
        step = max(1, step - 1)
    }

    /// Primary button on the footer. Step 1 kicks off sign-in then advances.
    /// Step 8 requests Apple Health authorization, records the result on
    /// the draft, then completes. Skip button bypasses the auth request.
    private func handlePrimary() {
        focusedField = nil
        switch step {
        case 1:
            Task { await performSignIn() }
        case 8:
            Task { await performConnectHealth() }
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
        focusedField = nil
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

    @MainActor
    private func performConnectHealth() async {
        connectingHealth = true
        defer { connectingHealth = false }
        await hkService.requestAuthorization()
        // requestAuthorization returns normally whether the user grants or
        // denies; isAuthorized is the post-decision truth. If the dialog
        // never appears (HK unavailable, simulator without HK store), the
        // flag stays false and the user can retry from Settings later.
        draft.appleHealthAuthorized = hkService.isAuthorized
        complete()
    }
}

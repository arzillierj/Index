import Foundation

/// Procedural HR series for demo workouts. Real HK-imported
/// workouts pull their samples from Apple Health via
/// `HealthKitService.fetchHRSeries`; demo workouts (no HK
/// record) need a believable in-memory series so the workout-
/// detail HR chart still renders.
///
/// The series is **deterministic per workout** — same workout
/// uuid → same samples. That stability matters because the user
/// expects the chart to look the same each time they open a
/// session, and because we don't want to recompute on every
/// tab return.
///
/// The shape is a realistic profile: a 90s warmup ramp, a
/// noisy plateau around the workout's avgHeartRate that peaks
/// near maxHeartRate, then a 60s cooldown. Sample density is
/// one per ~20 seconds (so a 60-minute workout has ~180 points,
/// matching what Apple Watch typically records).
enum DemoHRSeriesGenerator {

    /// One sample per ~20 seconds of workout duration. Returns
    /// an empty array if the workout has no HR summary stats
    /// (matching the no-data behavior of the real path).
    static func series(for session: WorkoutSession) -> [SwimHRSample] {
        guard session.hasHeartRate, session.durationMinutes > 0 else { return [] }

        let totalSeconds = max(60, session.durationMinutes * 60)
        let sampleInterval = 20
        let sampleCount = totalSeconds / sampleInterval

        let avg = Double(session.avgHeartRate)
        // Local is named `peak` (not `max`) to avoid shadowing
        // `Swift.max(_:_:)` inside this function.
        let peak = session.hasMaxHeartRate ? Double(session.maxHeartRate) : avg + 18
        // Resting baseline for the warmup ramp. ~25 bpm below
        // the average works for the typical aerobic range —
        // generic enough to not need per-workout tuning.
        let resting = avg - 25

        // Seeded by the workout's UUID (falls back to date
        // hashing for any session without one) so the series is
        // stable across re-opens.
        let seed = UInt64(bitPattern: Int64(
            (session.hkWorkoutUUID?.hashValue ?? Int(session.date.timeIntervalSince1970))
        ))
        var rng = SeededRNG(seed: seed)

        var samples: [SwimHRSample] = []
        samples.reserveCapacity(sampleCount)

        let warmupSamples  = sampleCount / 8       // ~12% warmup
        let cooldownSamples = sampleCount / 10     // ~10% cooldown
        let plateauStart = warmupSamples
        let plateauEnd   = sampleCount - cooldownSamples

        for i in 0..<sampleCount {
            let t = TimeInterval(i * sampleInterval)
            let date = session.date.addingTimeInterval(t)

            let bpm: Double
            if i < plateauStart {
                // Warmup — linear ramp from resting to avg.
                let progress = Double(i) / Double(plateauStart)
                bpm = resting + (avg - resting) * progress + rng.nextDouble(in: -2 ... 2)
            } else if i >= plateauEnd {
                // Cooldown — linear ramp from avg back to ~+10 of resting.
                let progress = Double(i - plateauEnd) / Double(sampleCount - plateauEnd)
                let cooldownEnd = resting + 10
                bpm = avg - (avg - cooldownEnd) * progress + rng.nextDouble(in: -2 ... 2)
            } else {
                // Plateau — sinusoidal variation around avg with
                // occasional spikes toward max. The spikes are
                // RNG-gated so they cluster believably (a couple
                // of pushes per session, not every sample).
                let phase = Double(i - plateauStart) / Double(Swift.max(1, plateauEnd - plateauStart))
                let wave = sin(phase * .pi * 6) * 6
                var hr = avg + wave + rng.nextDouble(in: -4 ... 4)
                if rng.nextDouble() < 0.08 {
                    // Brief peak toward max — 60–95% of the gap.
                    let push = (peak - avg) * rng.nextDouble(in: 0.6 ... 0.95)
                    hr = avg + push
                }
                bpm = hr
            }

            samples.append(SwimHRSample(date: date, bpm: bpm))
        }

        return samples
    }
}

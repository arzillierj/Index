import Foundation
import SwiftData

/// Audit log for photo-to-macros estimates so accuracy can be reviewed later.
/// `photoData` is downscaled JPEG bytes; nil if the user opted out of storage.
@Model
final class PhotoEstimateLog {
    var date: Date = Date.now
    var photoData: Data? = nil
    var estimatedKcal: Double = 0
    var estimatedProtein: Double = 0
    var estimatedCarbs: Double = 0
    var estimatedFat: Double = 0
    var userCorrected: Bool = false

    init(
        date: Date = .now,
        photoData: Data? = nil,
        estimatedKcal: Double = 0,
        estimatedProtein: Double = 0,
        estimatedCarbs: Double = 0,
        estimatedFat: Double = 0,
        userCorrected: Bool = false
    ) {
        self.date = date
        self.photoData = photoData
        self.estimatedKcal = estimatedKcal
        self.estimatedProtein = estimatedProtein
        self.estimatedCarbs = estimatedCarbs
        self.estimatedFat = estimatedFat
        self.userCorrected = userCorrected
    }
}

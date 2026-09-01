import Foundation

/// How much water counts as "a glass", and what the daily target is.
///
/// Tracked in millilitres rather than glasses. A glass is not a unit — yours may
/// be 200ml and mine 350ml — so a goal of "8 glasses" means nothing shared, and
/// health guidance is written in litres. The counter still *counts* glasses,
/// because that is what you actually do; it just knows what one is worth.
public struct WaterIntake: Codable, Equatable, Sendable {
    /// Millilitres in one glass.
    public var glassSize: Int
    /// Millilitres per day.
    public var dailyGoal: Int

    public init(glassSize: Int = 250, dailyGoal: Int = 3000) {
        self.glassSize = max(50, min(1000, glassSize))
        self.dailyGoal = max(250, min(10000, dailyGoal))
    }

    public static let `default` = WaterIntake()

    /// Common glass and bottle sizes.
    public static let glassSizeChoices = [150, 200, 250, 300, 330, 500]
    /// Daily targets, in millilitres.
    public static let goalChoices = [1500, 2000, 2500, 3000, 3500, 4000]

    /// How many glasses of this size make the daily goal, rounded up — you
    /// cannot drink four fifths of a glass and call the day done.
    public var glassesForGoal: Int {
        max(1, Int((Double(dailyGoal) / Double(glassSize)).rounded(.up)))
    }

    public func millilitres(forGlasses glasses: Int) -> Int {
        glasses * glassSize
    }

    public func hasReachedGoal(glasses: Int) -> Bool {
        millilitres(forGlasses: glasses) >= dailyGoal
    }

    /// 0...1 toward the daily goal.
    public func progress(glasses: Int) -> Double {
        guard dailyGoal > 0 else { return 0 }
        return min(1, Double(millilitres(forGlasses: glasses)) / Double(dailyGoal))
    }

    // MARK: Display

    /// "1.5 L" or "750 ml" — litres once it is worth using them.
    public static func format(millilitres: Int) -> String {
        if millilitres >= 1000 {
            let litres = Double(millilitres) / 1000
            return litres == litres.rounded()
                ? "\(Int(litres)) L"
                : String(format: "%.1f L", litres)
        }
        return "\(millilitres) ml"
    }

    /// "750 ml of 3 L" — the line shown in the menu and in Settings.
    public func summary(glasses: Int) -> String {
        "\(Self.format(millilitres: millilitres(forGlasses: glasses))) of \(Self.format(millilitres: dailyGoal))"
    }

    public var glassDescription: String {
        "\(glassSize) ml per glass · \(glassesForGoal) glasses a day"
    }
}

import Foundation

public let buildSteps: [(id: String, weight: Double)] = [
    ("extract", 5), ("verify", 5), ("patches", 5), ("prepare", 10),
    ("translate", 35), ("compile", 35), ("package", 5),
]

/// Fraction (0...1) of total work completed when the given step begins.
public func progressFraction(atStart stepID: String) -> Double {
    var sum = 0.0
    for step in buildSteps {
        if step.id == stepID { break }
        sum += step.weight
    }
    return sum / 100
}

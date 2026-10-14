//
//  NewGlucoseSample+Presentable.swift
//  LoopCaregiver
//
//  Created by Bill Gestrich on 6/3/23.
//

import Foundation
import HealthKit
import LoopKit

public extension NewGlucoseSample {
    func presentableUserValue(displayUnits: HKUnit) -> Double {
        return quantity.doubleValue(for: displayUnits)
    }

    func presentableStringValue(displayUnits: HKUnit, includeShortUnits: Bool) -> String {
        let unitInUserUnits = quantity.doubleValue(for: displayUnits)
        var result = LocalizationUtils.presentableStringFromGlucoseAmount(unitInUserUnits, displayUnits: displayUnits)
        if includeShortUnits {
            result += " " + displayUnits.shortLocalizedUnitString(avoidLineBreaking: true)
        }
        return result
    }
}

public extension [NewGlucoseSample] {
    func getLastGlucoseChange(displayUnits: HKUnit) -> Double? {
        guard count > 1 else {
            return nil
        }
        let sortedSamples = sorted(by: { $0.date < $1.date })
        let latestSample = sortedSamples[sortedSamples.count - 1]
        let lastGlucoseValue = latestSample.presentableUserValue(displayUnits: displayUnits)
        // 5-minute delta: compare the latest reading against the reading
        // closest to 5 minutes before it, not the immediately preceding
        // sample. The preceding sample can be a duplicate of the latest
        // reading written by a second uploader (same value, seconds to a
        // few minutes apart), which pinned the displayed delta at 0.
        // Falls back to the previous sample when none is old enough.
        var priorGlucoseValue = sortedSamples[sortedSamples.count - 2].presentableUserValue(displayUnits: displayUnits)
        let targetDate = latestSample.date.addingTimeInterval(-300)
        var bestTimeDiff = Double.greatestFiniteMagnitude
        for sample in sortedSamples.dropLast() where sample.date <= latestSample.date.addingTimeInterval(-240) {
            let diff = abs(sample.date.timeIntervalSince(targetDate))
            if diff < bestTimeDiff {
                bestTimeDiff = diff
                priorGlucoseValue = sample.presentableUserValue(displayUnits: displayUnits)
            }
        }
        return lastGlucoseValue - priorGlucoseValue
    }
}

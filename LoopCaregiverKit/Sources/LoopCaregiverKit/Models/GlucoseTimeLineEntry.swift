//
//  GlucoseTimeLineEntry.swift
//  LoopCaregiverKit
//
//  Created by Bill Gestrich on 12/18/23.
//

import Foundation
import HealthKit
import LoopKit
import NightscoutKit
import WidgetKit

public enum GlucoseTimeLineEntry: TimelineEntry, Hashable {
    case success(GlucoseTimelineValue)
    case failure(GlucoseTimeLineEntryError)
    
    public init(looper: Looper, glucoseSample: NewGlucoseSample, treatmentData: CaregiverTreatmentData, date: Date) {
        self = .success(
            GlucoseTimelineValue(
                looper: looper,
                glucoseSample: glucoseSample,
                treatmentData: treatmentData,
                date: date
            )
        )
    }
    
    public init(value: GlucoseTimelineValue) {
        self = .success(value)
    }
    
    public init(error: Error, date: Date, looper: Looper?) {
        self = .failure(GlucoseTimeLineEntryError(error: error, date: date, looper: looper))
    }
    
    public var date: Date {
        switch self {
        case .success(let glucoseEntry):
            return glucoseEntry.date
        case .failure(let error):
            return error.date
        }
    }
    
    public static func previewsEntry() -> GlucoseTimeLineEntry {
        return GlucoseTimeLineEntry(value: GlucoseTimelineValue.previewsValue())
    }
    
    public static func == (lhs: GlucoseTimeLineEntry, rhs: GlucoseTimeLineEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.success(lhsValue), .success(rhsValue)):
            return lhsValue == rhsValue
        case let (.failure(lhsError), .failure(rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

public struct GlucoseTimelineValue: Hashable {
    // TODO: It may be best to use the Looper ID and Looper name. Maybe introduce an entry configuration object for those? Need to consider if the name changes in Loop.
    public let looper: Looper
    public let glucoseSample: NewGlucoseSample
    public let treatmentData: CaregiverTreatmentData
    public let date: Date
    
    public init(
        looper: Looper,
        glucoseSample: NewGlucoseSample,
        treatmentData: CaregiverTreatmentData,
        date: Date
    ) {
        self.looper = looper
        self.glucoseSample = glucoseSample
        self.treatmentData = treatmentData
        self.date = date
    }
    
    public func nextExpectedGlucoseDate() -> Date {
        let secondsBetweenSamples: TimeInterval = 60 * 5
        return glucoseSample.date.addingTimeInterval(secondsBetweenSamples)
    }
    
    public func valueWithDate(_ date: Date) -> GlucoseTimelineValue {
        let treatmentData = CaregiverTreatmentData(
            creationDate: date,
            glucoseDisplayUnits: treatmentData.glucoseDisplayUnits,
            glucoseSamples: treatmentData.glucoseSamples,
            predictedGlucose: treatmentData.predictedGlucose,
            bolusEntries: treatmentData.bolusEntries,
            carbEntries: treatmentData.carbEntries,
            recentCommands: treatmentData.recentCommands,
            overrideAndStatus: treatmentData.overrideAndStatus,
            currentIOB: treatmentData.currentIOB,
            currentCOB: treatmentData.currentCOB,
            recommendedBolus: treatmentData.recommendedBolus
        )
        return .init(
            looper: looper,
            glucoseSample: glucoseSample,
            treatmentData: treatmentData,
            date: date
        )
    }
    
    public static func == (lhs: GlucoseTimelineValue, rhs: GlucoseTimelineValue) -> Bool {
        return lhs.looper.identifier == rhs.looper.identifier &&
               lhs.glucoseSample.date == rhs.glucoseSample.date &&
               lhs.treatmentData.creationDate == rhs.treatmentData.creationDate &&
               lhs.date == rhs.date
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(looper.identifier)
        hasher.combine(glucoseSample.date)
        hasher.combine(treatmentData.creationDate)
        hasher.combine(date)
    }
    
    public static func previewsValue() -> GlucoseTimelineValue {
        var recentSamples = [NewGlucoseSample]()
        for index in stride(from: 100, to: 200, by: 10) {
            recentSamples.append(
                NewGlucoseSample(
                    date: Date().addingTimeInterval(Double(-index * 60 * 5)),
                    quantity: .init(unit: .milligramsPerDeciliter, doubleValue: Double(60 + index)),
                    condition: .none,
                    trend: .flat,
                    trendRate: .none,
                    isDisplayOnly: false,
                    wasUserEntered: false,
                    syncIdentifier: "1345"
                )
            )
        }
        
        let treatmentData = CaregiverTreatmentData(
            glucoseDisplayUnits: .milligramsPerDeciliter,
            glucoseSamples: recentSamples,
            predictedGlucose: [],
            bolusEntries: [],
            carbEntries: [],
            recentCommands: [],
            currentProfile: nil,
            overrideAndStatus: nil,
            currentIOB: nil,
            currentCOB: nil,
            recommendedBolus: nil
        )
        
        return GlucoseTimelineValue(
            looper: Looper(
                identifier: UUID(),
                name: "Brian",
                nightscoutCredentials: .init(url: URL(string: "http://www.example.com")!, secretKey: "12345", otpURL: "12345"),
                lastSelectedDate: Date()
            ),
            glucoseSample: .previews(),
            treatmentData: treatmentData,
            date: Date()
        )
    }
}

public struct GlucoseTimeLineEntryError: LocalizedError, Hashable {
    let error: Error
    public let date: Date
    public let looper: Looper?
    public var errorDescription: String? {
        return error.localizedDescription
    }
    
    public static func == (lhs: GlucoseTimeLineEntryError, rhs: GlucoseTimeLineEntryError) -> Bool {
        return lhs.error.localizedDescription == rhs.error.localizedDescription &&
               lhs.date == rhs.date &&
               lhs.looper?.identifier == rhs.looper?.identifier
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(error.localizedDescription)
        hasher.combine(date)
        hasher.combine(looper?.identifier)
    }
}

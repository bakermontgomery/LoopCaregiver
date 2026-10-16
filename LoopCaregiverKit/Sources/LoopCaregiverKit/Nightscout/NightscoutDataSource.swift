//
//  NightscoutDataSource.swift
//  LoopCaregiver
//
//  Created by Bill Gestrich on 11/19/22.
//

import Foundation
import LoopKit
import NightscoutKit

public class NightscoutDataSource: ObservableObject, RemoteDataServiceProvider {
    private var credentialService: NightscoutCredentialService
    private let nightscoutUploader: NightscoutClient
    private let settings: CaregiverSettings
    private let treatmentsFetcher: NightscoutTreatmentFetcher

    public init(looper: Looper, settings: CaregiverSettings) {
        self.nightscoutUploader = NightscoutClient(siteURL: looper.nightscoutCredentials.url, apiSecret: looper.nightscoutCredentials.secretKey)
        self.credentialService = NightscoutCredentialService(credentials: looper.nightscoutCredentials)
        self.settings = settings
        self.treatmentsFetcher = NightscoutTreatmentFetcher(nightscoutClient: self.nightscoutUploader,
                                                            fetchLookbackInterval: Self.fetchLookbackInterval(),
                                                            fetchLookAheadInterval: Self.fetchLookAheadInterval(),
                                                            maxFetchCount: Self.maxFetchCount()
        )
    }

    // MARK: RemoteDataServiceProvider

    public func fetchGlucoseSamples() async throws -> [NewGlucoseSample] {
        return try await fetchGlucoseSamples(dateInterval: fetchInterval())
    }

    public func fetchGlucoseSamples(dateInterval: DateInterval) async throws -> [NewGlucoseSample] {
        let result = try await withCheckedThrowingContinuation({ continuation in
            nightscoutUploader.fetchGlucose(dateInterval: dateInterval, maxCount: maxFetchCount()) { result in
                continuation.resume(with: result)
            }
        })
        .map({ $0.toGlucoseSample() })
        if result.count >= maxFetchCount() {
            print("Hit max glucose count: Consider increasing")
        }
        return result
    }

    public func fetchRecentGlucoseSamples() async throws -> [NewGlucoseSample] {
        let maxCurrentMinutes = 30.0
        let earliestDate = Date().addingTimeInterval(-60 * maxCurrentMinutes)
        let dateInterval = DateInterval(start: earliestDate, end: Date())
        return try await fetchGlucoseSamples(dateInterval: dateInterval)
            .sorted(by: { $0.date < $1.date })
    }

    public func fetchBasalEntries() async throws -> [TempBasalNightscoutTreatment] {
        return try await treatmentsFetcher.fetchBasalEntries()
    }

    public func fetchBolusEntries() async throws -> [BolusNightscoutTreatment] {
        return try await treatmentsFetcher.fetchBolusEntries()
    }

    public func fetchCarbEntries() async throws -> [CarbCorrectionNightscoutTreatment] {
        return try await treatmentsFetcher.fetchCarbEntries()
    }

    public func fetchOverridePresets() async throws -> [OverrideTreatment] {
        return try await treatmentsFetcher.fetchOverridePresets()
    }

    func fetchNotes() async throws -> [NoteNightscoutTreatment] {
        return try await treatmentsFetcher.fetchNotes()
    }

    public func fetchLatestDeviceStatus() async throws -> DeviceStatus? {
        let result = try await withCheckedThrowingContinuation({ continuation in
            let fetchInterval = DateInterval(start: nowDate().addingTimeInterval(-60 * 60 * 2), end: fetchEndDate())
            nightscoutUploader.fetchDeviceStatus(dateInterval: fetchInterval) { result in
                continuation.resume(with: result)
            }
        })
        .sorted(by: { $0.timestamp < $1.timestamp })
        return result.last
    }

    func fetchStartDate() -> Date {
        return nowDate().addingTimeInterval(Self.fetchLookbackInterval())
    }

    static func fetchLookbackInterval() -> TimeInterval {
        return -60 * 60 * 24 * 1
    }

    func fetchEndDate() -> Date {
        return nowDate().addingTimeInterval(Self.fetchLookAheadInterval())
    }

    static func fetchLookAheadInterval() -> TimeInterval {
        return 60 * 60 * 4
    }

    func fetchInterval() -> DateInterval {
        return DateInterval(start: fetchStartDate(), end: fetchEndDate())
    }

    func maxFetchCount() -> Int {
        return Self.maxFetchCount()
    }

    static func maxFetchCount() -> Int {
        let seconds = abs(Self.fetchLookbackInterval()) + abs(Self.fetchLookbackInterval())
        let minutes = seconds / 60
        // Assume up to 2 entries every 1 minute.
        // We tried 1 entry per 5 minutes for bg, mulitplied by a factor for 2,
        // but this was not enoughf for some users.
        return Int(minutes * 2)
    }

    func nowDate() -> Date {
        return Date()
    }

    public func checkAuth() async throws {
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) -> Void in
            nightscoutUploader.checkAuth { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: Void())
                }
            }
        })
    }

    public func deliverCarbs(amountInGrams: Double, absorptionTime: TimeInterval, consumedDate: Date) async throws {
        // TODO: Ensure you get a valid OTP (non-empty String)
        await waitForFreshOTPIfNeeded()
        if settings.remoteCommands2Enabled {
            let action = NSRemoteAction.carbs(amountInGrams: amountInGrams, absorptionTime: absorptionTime, startDate: consumedDate)
            let commandPayload = createPendingCommand(action: action)
            _ = try await nightscoutUploader.uploadRemoteCommand(commandPayload)
        } else {
            try await nightscoutUploader.deliverCarbs(amountInGrams: amountInGrams, absorptionTime: absorptionTime, consumedDate: consumedDate, otp: credentialService.otpCode)
        }
    }

    public func deliverBolus(amountInUnits: Double) async throws {
        // TODO: Ensure you get a valid OTP (non-empty String)
        await waitForFreshOTPIfNeeded()
        if settings.remoteCommands2Enabled {
            let action = NSRemoteAction.bolus(amountInUnits: amountInUnits)
            let commandPayload = createPendingCommand(action: action)
            _ = try await nightscoutUploader.uploadRemoteCommand(commandPayload)
        } else {
            try await nightscoutUploader.deliverBolus(amountInUnits: amountInUnits, otp: credentialService.otpCode)
        }
    }

    public func startOverride(overrideName: String, durationTime: TimeInterval) async throws {
        if settings.remoteCommands2Enabled {
            // TODO: remoteAddress should be optional
            let action = NSRemoteAction.override(name: overrideName, durationTime: durationTime, remoteAddress: "")
            let commandPayload = createPendingCommand(action: action)
            _ = try await nightscoutUploader.uploadRemoteCommand(commandPayload)
        } else {
            try await nightscoutUploader.startOverride(overrideName: overrideName, reasonDisplay: "Caregiver Update", durationTime: durationTime)
        }
    }

    public func cancelOverride() async throws {
        if settings.remoteCommands2Enabled {
            // TODO: remoteAddress should be optional
            let action = NSRemoteAction.cancelOverride(remoteAddress: "")
            let commandPayload = createPendingCommand(action: action)
            _ = try await nightscoutUploader.uploadRemoteCommand(commandPayload)
        } else {
            try await nightscoutUploader.cancelOverride()
        }
    }

    public func activateAutobolus(activate: Bool) async throws {
        let action = NSRemoteAction.autobolus(active: activate)
        let commandPayload = createPendingCommand(action: action)
        _ = try await nightscoutUploader.uploadRemoteCommand(commandPayload)
    }

    public func activateClosedLoop(activate: Bool) async throws {
        let action = NSRemoteAction.closedLoop(active: activate)
        let commandPayload = createPendingCommand(action: action)
        _ = try await nightscoutUploader.uploadRemoteCommand(commandPayload)
    }

    public func fetchCurrentProfile() async throws -> ProfileSet {
        return try await withCheckedThrowingContinuation { continuation in
            nightscoutUploader.fetchCurrentProfile { result in
                continuation.resume(with: result)
            }
        }
    }

    func createPendingCommand(action: NSRemoteAction) -> NSRemoteCommandPayload {
        return NSRemoteCommandPayload(version: "2.0", createdDate: Date(), action: action, sendNotification: true, status: .init(state: .Pending, message: ""), otp: credentialService.otpCode)
    }

    public func fetchRecentCommands() async throws -> [RemoteCommand] {
        let commands: [RemoteCommand]
        if settings.remoteCommands2Enabled {
            commands = try await nightscoutUploader.fetchRemoteCommands(earliestDate: fetchInterval().start, commandState: nil).compactMap({ try? $0.toRemoteCommand() })
        } else {
            commands = try await fetchNotes()
                .compactMap({ $0.toRemoteCommand() })
        }
        retryOTPExpiredCommandsIfNeeded(commands)
        return commands
    }

    // MARK: - OTP freshness + one automatic retry on an expired-password rejection

    /// One-time passwords rotate every 30 seconds and Loop accepts only the
    /// last two. If a command is sent in the final seconds of a step, normal
    /// delivery delay can age its password out before Loop processes it, so
    /// when a step is nearly over, wait for the next password first.
    private func waitForFreshOTPIfNeeded() async {
        let step: TimeInterval = 30
        let remaining = step - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: step)
        guard remaining < 10 else { return }
        try? await Task.sleep(nanoseconds: UInt64((remaining + 0.5) * 1_000_000_000))
    }

    /// If a recent bolus/carbs command failed only because its one-time
    /// password expired ("Only the last 2 passwords are accepted"), Loop did
    /// not act on it, so resend the same command once with a fresh password.
    /// Each failed command is retried at most once, ever.
    private func retryOTPExpiredCommandsIfNeeded(_ commands: [RemoteCommand]) {
        let defaultsKey = "OTPExpiredRetriedCommandIDs"
        var retriedIDs = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])

        for command in commands {
            guard case .error = command.status.state else { continue }
            let message = command.status.message
            guard message.localizedCaseInsensitiveContains("last 2 passwords"),
                  message.localizedCaseInsensitiveContains("expired")
            else { continue }
            // Only retry fresh failures, and only once per command.
            guard Date().timeIntervalSince(command.createdDate) < 15 * 60 else { continue }
            guard !retriedIDs.contains(command.id) else { continue }

            switch command.action {
            case let .bolusEntry(action):
                retriedIDs.insert(command.id)
                Task {
                    try? await self.deliverBolus(amountInUnits: action.amountInUnits)
                }
            case let .carbsEntry(action):
                retriedIDs.insert(command.id)
                Task {
                    try? await self.deliverCarbs(
                        amountInGrams: action.amountInGrams,
                        absorptionTime: action.absorptionTime ?? 3 * 3600,
                        consumedDate: action.startDate ?? Date()
                    )
                }
            default:
                continue
            }
        }

        // Persist the retried set, capped so it cannot grow without bound.
        UserDefaults.standard.set(Array(retriedIDs.suffix(50)), forKey: defaultsKey)
    }

    public func deleteAllCommands() async throws {
        if settings.remoteCommands2Enabled {
            try await nightscoutUploader.deleteRemoteCommands()
        } else {
            assertionFailure("Remote 2.0 commands are not enabled.")
        }
    }
}

actor NightscoutTreatmentFetcher {
    private weak var nightscoutClient: NightscoutClient?
    private var lastTreatmentFetch: (fetchDate: Date, treatments: [NightscoutTreatment])?
    private var fetchTaskInProgress: Task<[NightscoutTreatment], Error>?
    private let fetchLookbackInterval: TimeInterval
    private let fetchLookAheadInterval: TimeInterval
    private let maxFetchCount: Int

    init(nightscoutClient: NightscoutClient,
         fetchLookbackInterval: TimeInterval,
         fetchLookAheadInterval: TimeInterval,
         maxFetchCount: Int
    ) {
        self.nightscoutClient = nightscoutClient
        self.fetchLookbackInterval = fetchLookbackInterval
        self.fetchLookAheadInterval = fetchLookAheadInterval
        self.maxFetchCount = maxFetchCount
    }

    func fetchBasalEntries() async throws -> [TempBasalNightscoutTreatment] {
        return try await fetchTreatments()
            .basalTreatments()
    }

    func fetchBolusEntries() async throws -> [BolusNightscoutTreatment] {
        return try await fetchTreatments()
            .bolusTreatments()
    }

    func fetchCarbEntries() async throws -> [CarbCorrectionNightscoutTreatment] {
        return try await fetchTreatments()
            .carbTreatments()
    }

    func fetchOverridePresets() async throws -> [OverrideTreatment] {
        return try await fetchTreatments()
            .overrideTreatments()
    }

    func fetchNotes() async throws -> [NoteNightscoutTreatment] {
        return try await fetchTreatments()
            .noteTreatments()
    }

    func fetchTreatments() async throws -> [NightscoutTreatment] {
        if let ongoingFetch = fetchTaskInProgress {
            return try await ongoingFetch.value
        }
        
        if let validCachedTreatments = getValidCachedTreatments() {
            return validCachedTreatments
        }
        
        let task = Task { [self] in
            do {
                let treatments = try await fetchTreatmentsNoCache()
                fetchTaskInProgress = nil
                lastTreatmentFetch = (fetchDate: Date(), treatments: treatments)
                return treatments
            } catch {
                fetchTaskInProgress = nil
                throw error
            }
        }
        fetchTaskInProgress = task
        let treatments = try await task.value
        storeCachedTreatments(treatments: treatments)
        return treatments
    }

    func fetchTreatmentsNoCache() async throws -> [NightscoutTreatment] {
        guard let nightscoutClient = self.nightscoutClient else {return []}
        return try await withCheckedThrowingContinuation({ continuation in
            nightscoutClient.fetchTreatments(dateInterval: fetchInterval(), maxCount: maxFetchCount) { result in
                continuation.resume(with: result)
            }
        })
    }

    private func storeCachedTreatments(treatments: [NightscoutTreatment]) {
        lastTreatmentFetch = (fetchDate: Date(), treatments: treatments)
    }

    private func getValidCachedTreatments() -> [NightscoutTreatment]? {
        guard let lastTreatmentFetch else {
            return nil
        }

        let now = nowDate()

        guard lastTreatmentFetch.fetchDate <= now else {
            return nil // Future date - invalid
        }

        guard lastTreatmentFetch.fetchDate >= now.addingTimeInterval(-15) else {
            return nil
        }

        return lastTreatmentFetch.treatments
    }

    private func nowDate() -> Date {
        return Date()
    }

    private func fetchStartDate() -> Date {
        return nowDate().addingTimeInterval(fetchLookbackInterval)
    }

    func fetchEndDate() -> Date {
        return nowDate().addingTimeInterval(fetchLookAheadInterval)
    }

    func fetchInterval() -> DateInterval {
        return DateInterval(start: fetchStartDate(), end: fetchEndDate())
    }
}

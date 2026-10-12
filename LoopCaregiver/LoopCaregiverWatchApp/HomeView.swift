//
//  HomeView.swift
//  LoopCaregiverWatchApp
//
//  Created by Bill Gestrich on 12/18/23.
//

import LoopCaregiverKit
import LoopCaregiverKitUI
import SwiftUI
import WidgetKit

struct HomeView: View {
    @ObservedObject var connectivityManager: WatchService
    @ObservedObject var accountService: AccountServiceManager
    @ObservedObject var remoteDataSource: RemoteDataServiceManager
    @ObservedObject var settings: CaregiverSettings
    @ObservedObject var looperService: LooperService
    @Environment(\.scenePhase)
    var scenePhase
    
    init(connectivityManager: WatchService, accountService: AccountServiceManager, looperService: LooperService) {
        self.connectivityManager = connectivityManager
        self.looperService = looperService
        self.settings = accountService.settings
        self.accountService = accountService
        self.remoteDataSource = looperService.remoteDataSource
    }
    
    var body: some View {
        GeometryReader { geometryProxy in
            List {
                graphRowView()
                    .frame(height: geometryProxy.size.height * 0.75)
                    .listRowBackground(Color.clear)
                NavigationLink {
                    Text("Override Control Coming Soon...")
                } label: {
                    overrideRowView()
                }
                NavigationLink {
                    WatchSettingsView(
                        connectivityManager: connectivityManager,
                        accountService: accountService,
                        settings: settings
                    )
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // Use separate view to avoid the entire body from updating when remoteDataSource.updating changes
                ToolbarButtonView(remoteDataSource: remoteDataSource, glucoseTimelineEntry: glucoseTimelineEntry)
                // Workaround for iOS 26 Beta issue FB19330113
                    .id(glucoseTimelineEntry)
            }
        }
        .onChange(of: scenePhase, { _, _ in
            updateData()
        })
    }
    
    @ViewBuilder
    func graphRowView() -> some View {
        Group {
            switch glucoseTimelineEntry {
            case .success:
                NightscoutChartScrollView(settings: settings, remoteDataSource: remoteDataSource, compactMode: true)
            case .failure(let glucoseTimeLineEntryError):
                if !remoteDataSource.updating {
                    Text(glucoseTimeLineEntryError.localizedDescription)
                } else {
                    Text("")
                }
            }
        }
    }
    
    @ViewBuilder
    func overrideRowView() -> some View {
        switch glucoseTimelineEntry {
        case .success(let glucoseTimelineValue):
            if let (override, status) = glucoseTimelineValue.treatmentData.overrideAndStatus {
                Label {
                    if status.active {
                        Text(override.presentableDescription())
                    } else {
                        Text("Overrides")
                    }
                } icon: {
                    workoutImage(isActive: status.active)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.blue)
                        .accessibilityLabel(Text("Workout"))
                }
            }
        case .failure:
            Text("")
        }
    }
    
    struct ToolbarButtonView: View {
        var remoteDataSource: RemoteDataServiceManager
        var glucoseTimelineEntry: GlucoseTimeLineEntry
        
        var body: some View {
            Button(action: {
                Task {
                    await remoteDataSource.updateData()
                }
            }, label: {
                ZStack {
                    switch glucoseTimelineEntry {
                    case .success(let glucoseTimelineValue):
                        LatestGlucoseRowView(glucoseValue: glucoseTimelineValue)
                    case .failure:
                        // Workaround: Empty text for iOS 26 Beta issue FB19330113
                        Text("                                     ")
                    }
                    ProgressView()
                        .opacity(remoteDataSource.updating ? 1.0 : 0.0)
                        .allowsHitTesting(false)
                }
            })
        }
    }
    
    func workoutImage(isActive: Bool) -> Image {
        if overrideIsActive() {
            return Image.workoutSelected
        } else {
            return Image.workout
        }
    }
    
    private func overrideIsActive() -> Bool {
        remoteDataSource.activeOverride() != nil
    }
    
    @MainActor
    private func updateData() {
        Task {
            await looperService.remoteDataSource.updateData()
        }
    }
    
    private var glucoseTimelineEntry: GlucoseTimeLineEntry {
        let sortedSamples = remoteDataSource.glucoseSamples
        guard let latestGlucoseSample = sortedSamples.last else {
            return GlucoseTimeLineEntry(error: WatchViewError.missingGlucose, date: Date(), looper: looperService.looper)
        }
        let treatmentData = CaregiverTreatmentData(
            glucoseDisplayUnits: settings.glucosePreference.unit,
            glucoseSamples: sortedSamples,
            predictedGlucose: remoteDataSource.predictedGlucose,
            bolusEntries: remoteDataSource.bolusEntries,
            carbEntries: remoteDataSource.carbEntries,
            recentCommands: remoteDataSource.recentCommands,
            overrideAndStatus: remoteDataSource.activeOverrideAndStatus(),
            currentIOB: remoteDataSource.currentIOB,
            currentCOB: remoteDataSource.currentCOB,
            recommendedBolus: remoteDataSource.recommendedBolus
        )
        let value = GlucoseTimelineValue(
            looper: looperService.looper,
            glucoseSample: latestGlucoseSample,
            treatmentData: treatmentData,
            date: Date()
        )
        return GlucoseTimeLineEntry(value: value)
    }
    
    private enum WatchViewError: LocalizedError {
        case missingGlucose
        
        var errorDescription: String? {
            switch self {
            case .missingGlucose:
                return "Missing glucose"
            }
        }
    }
}

#Preview {
    let composer = ServiceComposerPreviews()
    return NavigationStack {
        if let looper = try? composer.accountServiceManager.getLoopers().first {
            let looperService = composer.accountServiceManager.createLooperService(
                looper: looper
            )
            HomeView(connectivityManager: composer.watchService, accountService: composer.accountServiceManager, looperService: looperService)
        } else {
            Text("No looper!")
        }
    }
}

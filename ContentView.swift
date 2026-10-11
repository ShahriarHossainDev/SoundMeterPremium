import SwiftUI

enum AppTab: Int, CaseIterable {
    case camera = 0
    case dosimeter = 1
    case meter = 2
    case data = 3
    case settings = 4

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .dosimeter: return "Dosimeter"
        case .meter: return "Meter"
        case .data: return "Data"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera"
        case .dosimeter: return "headphones"
        case .meter: return "gauge.with.dots.needle.67percent"
        case .data: return "list.bullet"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct RootTabView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: AppTab = .meter

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    CameraView(onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = .meter
                        }
                    })
                }
                .tag(AppTab.camera)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack { DosimeterView() }
                    .tag(AppTab.dosimeter)
                    .toolbar(.hidden, for: .tabBar)

                NavigationStack { MeterView() }
                    .tag(AppTab.meter)
                    .toolbar(.hidden, for: .tabBar)

                HistoryView()
                    .tag(AppTab.data)
                    .toolbar(.hidden, for: .tabBar)

                SettingsView()
                    .tag(AppTab.settings)
                    .toolbar(.hidden, for: .tabBar)
            }
            .ignoresSafeArea(edges: .bottom)

            .onReceive(NotificationCenter.default.publisher(for: .switchToMeterTab)) { _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTab = .meter
                }
            }

            // Custom Floating Dark Pill Bottom Navigation Bar matching screenshot
            if selectedTab != .camera {
                CustomBottomTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if $0 { hasCompletedOnboarding = false } }
        )) {
            OnboardingView()
        }
    }
}

struct CustomBottomTabBar: View {
    @Binding var selectedTab: AppTab

    private let vibrantOrange = Color(red: 1.0, green: 0.44, blue: 0.18)
    private let barBackground = Color(red: 0.07, green: 0.09, blue: 0.13)
    private let selectedHighlight = Color(red: 0.02, green: 0.03, blue: 0.05)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        if tab == .meter {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isSelected ? vibrantOrange : Color.white.opacity(0.85), lineWidth: 1.5)
                                    .frame(width: 24, height: 18)

                                Text("dB")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSelected ? vibrantOrange : Color.white.opacity(0.85))
                            }
                            .frame(height: 20)
                        } else {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? vibrantOrange : Color.white.opacity(0.85))
                        }

                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? vibrantOrange : Color.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(selectedHighlight)
                                    .padding(.horizontal, 2)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(barBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 6)
        )
    }
}

struct SpectrumView: View {
    @StateObject private var model = SpectrumViewModel()
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PremiumCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Frequency Analyzer", systemImage: "waveform.path")
                            .font(.title2.bold())
                        Text("Live FFT frequency analyzer using the device microphone.")
                            .foregroundStyle(.secondary)
                    }
                }

                PremiumCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Live spectrum").font(.headline)
                            Spacer()
                            Text(model.dominantFrequency > 0 ? String(format: "%.0f Hz", model.dominantFrequency) : "Listening…")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(Array(model.bars.enumerated()), id: \.offset) { _, height in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [AppTheme.accent, AppTheme.secondaryAccent], startPoint: .bottom, endPoint: .top))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 130 * CGFloat(height))
                            }
                        }
                        Text("Dominant frequency is the strongest FFT bin. Results are for indication, not laboratory analysis.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Spectrum")
        .task { model.start() }
        .onDisappear { model.stop() }
        .alert("Spectrum", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}


extension Notification.Name {
    static let switchToMeterTab = Notification.Name("switchToMeterTab")
}

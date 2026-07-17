import Foundation
import CoreLocation
import SwiftUI

/// Shares the owner's rough location with Edwin (opt-in, Assistant Settings).
/// When-in-use only: refreshes whenever the app comes to the foreground, so
/// Edwin knows "you're in Shoreditch" without tracking in the background.
@MainActor
final class LocationStore: NSObject, ObservableObject {
    static let shared = LocationStore()
    private let mgr = CLLocationManager()
    @AppStorage("assistant.shareLocation") var enabled = false
    var auth: AuthStore?
    @Published var lastPlace: String?

    override private init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Call on foreground / after enabling. No-op when the toggle is off.
    func refresh() {
        guard enabled else { return }
        switch mgr.authorizationStatus {
        case .notDetermined: mgr.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: mgr.requestLocation()
        default: break
        }
    }

    /// Toggle off → forget the stored location server-side too.
    func clear() {
        guard let token = auth?.accessToken, let userId = auth?.userId else { return }
        Task {
            var req = URLRequest(url: URL(string: "\(GoogleAuth.projectURL)/rest/v1/assistant_location?user_id=eq.\(userId)")!)
            req.httpMethod = "DELETE"
            req.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
            lastPlace = nil
        }
    }

    private func upload(_ loc: CLLocation) async {
        guard enabled, let token = auth?.accessToken, let userId = auth?.userId, !userId.isEmpty else { return }
        var placeName: String? = nil
        if let pm = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
            placeName = [pm.subLocality, pm.locality].compactMap { $0 }.uniqued().joined(separator: ", ")
            if placeName?.isEmpty == true { placeName = pm.name }
        }
        lastPlace = placeName
        var req = URLRequest(url: URL(string: "\(GoogleAuth.projectURL)/rest/v1/assistant_location?on_conflict=user_id")!)
        req.httpMethod = "POST"
        req.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "user_id": userId,
            "lat": loc.coordinate.latitude, "lon": loc.coordinate.longitude,
            "place": placeName ?? "",
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ])
        _ = try? await URLSession.shared.data(for: req)
    }
}

extension LocationStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in await self.upload(l) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

private extension Array where Element == String {
    func uniqued() -> [String] { var seen = Set<String>(); return filter { seen.insert($0).inserted } }
}

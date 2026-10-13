#if DEBUG
import SwiftUI

struct BackendDebugView: View {
    @State private var status = "Not tested"
    @State private var detail = "Test the configured project by reading its category catalog."
    @State private var isTesting = false
    @State private var attempt = 0

    var body: some View {
        Form {
            Section("Backend Status") {
                Text(status).font(AppTypography.headline)
                Text(detail).foregroundStyle(AppColors.secondaryText)
                if isTesting { ProgressView("Checking connection…") }
                Button("Test Supabase Connection") {
                    isTesting = true
                    status = "Testing"
                    detail = "Reading categories…"
                    attempt += 1
                }
                .frame(minHeight: 44)
                .disabled(isTesting)
            }
            Section("Development only") {
                Text("Configure Configuration/Config.xcconfig and rebuild. Never use a service-role or secret key. This screen is excluded from Release builds.")
                Text("The connection test does not sign in, change database rows, or replace the mock feed.")
            }
        }
        .navigationTitle("Backend Connection")
        .task(id: attempt) {
            if attempt == 0 {
                do {
                    _ = try SupabaseConfiguration.load()
                } catch {
                    show(error)
                }
                return
            }
            defer { isTesting = false }
            do {
                let count = try await SupabaseConnectionChecker().check()
                try Task.checkCancellation()
                status = "Connected — \(count) categories found"
                detail = count == 12
                    ? "The expected category catalog was received from Supabase."
                    : "Connection succeeded. The initial migration seeds 12 categories; verify the catalog if this count is unexpected."
            } catch is CancellationError {
                status = "Not tested"
                detail = "The connection test was cancelled."
            } catch {
                show(error)
            }
        }
    }

    private func show(_ error: Error) {
        if let error = error as? DatabaseError {
            switch error {
            case .notConfigured: status = "Not configured"
            default: status = "Failed"
            }
            detail = error.localizedDescription + " Update Configuration/Config.xcconfig and rebuild."
        } else if let error = error as? SupabaseConnectionChecker.ConnectionError {
            status = "Failed"
            detail = error.localizedDescription
        } else {
            status = "Failed"
            detail = "The connection test could not finish. Please try again."
        }
    }
}

#Preview {
    NavigationStack { BackendDebugView() }
}
#endif

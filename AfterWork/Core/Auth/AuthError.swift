import Foundation

nonisolated enum AppAuthError: Error, LocalizedError {
    case appleCredential, nonce, callback, browser, invalidProfile

    var errorDescription: String? {
        switch self {
        case .appleCredential: "Apple couldn't complete sign-in. Please try again."
        case .nonce: "We couldn't start secure sign-in. Please try again."
        case .callback: "The sign-in response wasn't valid. Please start again."
        case .browser: "We couldn't open the sign-in window. Please try again."
        case .invalidProfile: "Enter a display name of 1–100 characters."
        }
    }
}

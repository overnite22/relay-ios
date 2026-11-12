import LocalAuthentication

/// Face ID / Touch ID / code de l'iPhone avant d'afficher un secret du coffre.
enum Biometrics {
    static let settingKey = "requireBiometrics"

    static var required: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    /// Demande l'authentification si nécessaire ; mémorise le déverrouillage 60 secondes.
    @MainActor static func unlock(_ app: AppSession, reason: String = "Afficher un secret du coffre Relay") async -> Bool {
        if !required || app.secretsUnlocked { return true }
        let ok = await authenticate(reason: reason)
        if ok { app.markUnlocked() }
        return ok
    }
}

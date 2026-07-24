import SwiftUI
#if canImport(Translation)
import Translation
#endif

// MARK: - View extension

extension View {
    /// On macOS 15+, when the vocabulary panel appears, retranslates any
    /// pending entries if the Apple session is already live.
    ///
    /// Session lifecycle is managed by `TranslationSessionHost` (an invisible
    /// persistent window), so this modifier never creates or invalidates a
    /// session configuration — it only triggers a catch-up retry on panel open.
    ///
    /// On macOS < 15, this is a no-op; the service falls back to LibreTranslate.
    @ViewBuilder
    func retryPendingOnAppear(for service: TranslationService) -> some View {
        if #available(macOS 15, *) {
            self.modifier(RetryOnAppearModifier(service: service))
        } else {
            self
        }
    }
}

// MARK: - Modifier

@available(macOS 15, *)
private struct RetryOnAppearModifier: ViewModifier {
    let service: TranslationService

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Always call — retryPendingTranslations() is a no-op when nothing is pending,
                // and the session may have become ready between launch and panel open (FR-005).
                Task { await service.retryPendingTranslations() }
            }
    }
}

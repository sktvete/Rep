import Testing
@testable import Rep

@Suite("Rest timer notifications")
struct RestTimerNotificationTests {
    @Test("The timer has 40 distinct encouragement messages")
    @MainActor
    func messageCatalog() {
        #expect(RestTimerNotificationManager.messages.count == 40)
        #expect(Set(RestTimerNotificationManager.messages).count == 40)
        #expect(RestTimerNotificationManager.messages.contains("Get back to work, champ!"))

        let discouragingPhrases = ["not enough", "lazy", "weak", "failure", "punishment"]
        for message in RestTimerNotificationManager.messages {
            let normalized = message.lowercased()
            #expect(discouragingPhrases.allSatisfy { !normalized.contains($0) })
        }
    }
}

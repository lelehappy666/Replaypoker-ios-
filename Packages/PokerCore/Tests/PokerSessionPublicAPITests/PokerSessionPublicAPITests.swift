import PokerCore
import PokerSession
import Testing

@Test func sessionPrimitivesArePubliclyAvailable() throws {
    #expect(try BusinessID("business-1").rawValue == "business-1")
    #expect(SessionEconomy.initialBalance == (try Chips(128_500)))
}

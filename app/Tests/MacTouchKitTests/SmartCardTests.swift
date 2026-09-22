import Testing
@testable import MacTouchKit

@Suite struct SmartCardIdentitiesParsing {
  @Test func picksThisDevicesIdentitiesBySection() {
    let text = """
    SmartCard: com.apple.pivtoken:5C9FE73E0C2747AEA4406000134C80D6
    Paired identities:
    AAAA\tCertificate For PIV Authentication (Some Other Card)
    Unpaired identities:
    087557DFAD568FF656A362538FDEF15CA734430D\tCertificate For PIV Authentication (mactouch PIV Authentication)
    """
    let identities = SmartCardIdentities.parse(text)
    #expect(identities.paired.isEmpty)
    #expect(identities.unpaired == [.init(hash: "087557DFAD568FF656A362538FDEF15CA734430D",
                                          name: "Certificate For PIV Authentication (mactouch PIV Authentication)")])
  }

  @Test func emptyWhenNothingIsListed() {
    #expect(SmartCardIdentities.parse("SmartCard: com.apple.pivtoken:X\n") == SmartCardIdentities())
  }
}

/// Bound retries without advancing the campaign while its UI is unavailable.
public struct CampaignBackoff: Sendable {
  public private(set) var delaySeconds = 0.0

  public init() {}

  @discardableResult
  public mutating func failed() -> Double {
    delaySeconds = min(60, max(5, delaySeconds * 2))
    return delaySeconds
  }

  public mutating func recovered() {
    delaySeconds = 0
  }
}

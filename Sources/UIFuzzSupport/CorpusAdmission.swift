import Foundation

public enum CorpusAdmission {
  /// The runner records an action before performing it, so a run that stopped because the driver
  /// could not perform its last action ends with an action that never ran; the corpus copy omits
  /// it. A crash, hang, or correctness finding keeps the whole trace, as the last action may have
  /// caused it.
  public static func trace(for report: ExecutionReport) -> FuzzTrace? {
    let kinds = Set(report.findings.map(\.kind))
    guard report.actionMilliseconds.count < report.trace.actions.count,
      kinds.contains(.automation), kinds.isDisjoint(with: [.crash, .hang, .correctness])
    else { return report.trace }
    var admitted = report.trace
    admitted.actions = Array(report.trace.actions.prefix(report.actionMilliseconds.count))
    return admitted.actions.isEmpty ? nil : admitted
  }
}

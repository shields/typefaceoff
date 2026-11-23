// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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

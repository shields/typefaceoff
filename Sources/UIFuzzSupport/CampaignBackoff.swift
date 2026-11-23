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

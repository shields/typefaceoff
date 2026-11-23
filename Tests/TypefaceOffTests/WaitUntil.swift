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

import Testing

@MainActor func waitUntil(
  _ condition: () -> Bool, describing state: @autoclosure () -> String = "",
  step: () async throws -> Void = { try await Task.sleep(for: .milliseconds(10)) },
  sourceLocation: SourceLocation = #_sourceLocation
) async throws {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition(), ContinuousClock.now < deadline {
    try await step()
  }
  #expect(condition(), "Timed out after 10 seconds. \(state())", sourceLocation: sourceLocation)
}

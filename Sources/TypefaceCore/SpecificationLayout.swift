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

public struct SpecificationLayout: Equatable, Sendable {
  public let width: Double
  public let compact: Bool
  public let showsTypography: Bool

  public init(width: Double, inspectorOpen: Bool) {
    self.width = width
    compact = width < 1240 || inspectorOpen
    showsTypography = width >= 1120 && !inspectorOpen
  }

  public var style: Double { width * 0.2 + 96 }
  public var size: Double { (width + 64) / 2 }
  public var weight: Double { size + 88 }
  public var leading: Double { size + (compact ? 152 : 160) }
  public var tracking: Double { size + (compact ? 248 : 264) }
  public var typography: Double { size + (compact ? 344 : 400) }
  public var indexControls: Double { compact ? tracking : typography }
  public var familyWidth: Double { style - 80 }
  public var styleWidth: Double { size - style - 32 }
  public var weightFieldWidth: Double { compact ? 58 : 66 }
  public var trackingFieldWidth: Double {
    let fieldWidth = compact ? 90.0 : 122
    return showsTypography ? fieldWidth : min(fieldWidth, width - tracking - 118)
  }
}

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

import AppKit
import SwiftUI
import TypefaceCore

struct TextComparisonView: View {
  let comparison: Comparison
  let highlights: Set<String>
  let highlightKinds: [String: String]
  let scrollPosition: SpecimenScrollPosition
  let select: (String) -> Void
  @State private var measuredBaselines: [Side: Double]

  init(
    comparison: Comparison, highlights: Set<String>, highlightKinds: [String: String],
    scrollPosition: SpecimenScrollPosition, select: @escaping (String) -> Void
  ) {
    self.comparison = comparison
    self.highlights = highlights
    self.highlightKinds = highlightKinds
    self.scrollPosition = scrollPosition
    self.select = select
    _measuredBaselines = State(initialValue: [:])
  }

  private var canCompare: Bool {
    FontRenderer.isAvailable(comparison.a)
      && comparison.b.map { FontRenderer.isAvailable($0) } == true
  }

  private var baseline: Double {
    let layout = NSLayoutManager()
    return [Side.a, .b].reduce(50) { baseline, side in
      guard let config = comparison[side], FontRenderer.isAvailable(config) else { return baseline }
      let measured =
        measuredBaselines[side]
        ?? layout.defaultBaselineOffset(for: FontRenderer.font(config) as NSFont)
      return max(baseline, measured + 8)
    }
  }

  var body: some View {
    GeometryReader { geometry in
      let width = max(0, (geometry.size.width - 192) / 2)
      let baseline = baseline
      HStack(spacing: 64) {
        column(.a, baseline: baseline).frame(width: width)
        column(.b, baseline: baseline).frame(width: width)
      }.padding(.horizontal, 64)
    }.background(WorkbenchStyle.paper)
  }

  private func column(_ side: Side, baseline: Double) -> some View {
    let config = comparison[side]
    let installed = config.map { FontRenderer.isAvailable($0) } == true
    return ZStack(alignment: .topLeading) {
      if let config {
        if installed {
          SpecimenText(
            config: config, text: comparison.text, sample: comparison.sample,
            inset: .zero, firstBaseline: (baseline, { measuredBaselines[side] = $0 }),
            lineFragmentPadding: 0,
            highlights: canCompare ? highlights : [], highlightKinds: highlightKinds,
            side: side, scrollPosition: scrollPosition, select: select)
        } else {
          Text("This font is not installed.\nChoose an installed font above.")
            .font(.system(size: 15)).foregroundStyle(WorkbenchStyle.secondaryInk)
            .alignmentGuide(.top) { $0[.firstTextBaseline] }.offset(y: baseline)
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .overlay(alignment: .topLeading) {
        Text(side == .a ? "A" : "B").font(.system(size: 13, weight: .bold))
          .foregroundStyle(
            installed
              ? Color(nsColor: side == .a ? WorkbenchStyle.red : WorkbenchStyle.blue)
              : WorkbenchStyle.secondaryInk
          ).alignmentGuide(.top) { $0[.firstTextBaseline] }.offset(x: -24, y: baseline)
      }
  }
}

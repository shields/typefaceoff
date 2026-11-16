import SwiftUI
import TypefaceCore

struct LanguageFilters: View {
  @ObservedObject var browser: LanguageBrowserModel
  let comparing: Bool
  @State private var threshold: String

  init(browser: LanguageBrowserModel, comparing: Bool) {
    self.browser = browser
    self.comparing = comparing
    _threshold = State(initialValue: SpeakerThreshold.format(browser.filter.minimumSpeakers))
  }

  var body: some View {
    GeometryReader { geometry in
      let width = max(960, geometry.size.width)
      let column = (width - 192) / 2
      let compact = width < 1240
      HStack(alignment: .top, spacing: 0) {
        if !compact {
          Text("Minimum speakers").foregroundStyle(WorkbenchStyle.secondaryInk)
            .frame(width: 132, height: 24, alignment: .leading)
        }
        VStack(alignment: .leading, spacing: 0) {
          if compact {
            Text("Minimum speakers").foregroundStyle(WorkbenchStyle.secondaryInk)
              .font(.system(size: 11)).frame(height: 18)
          }
          HStack(alignment: .top, spacing: 20) {
            slider.frame(width: column - (compact ? 84 : 216))
            speakerField.frame(width: 64, height: 24)
          }
        }
      }.offset(x: 64, y: compact ? 6 : 20)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 16) {
          coverage
          Toggle("Show historical", isOn: $browser.filter.showHistorical).toggleStyle(.checkbox)
            .accessibilityIdentifier("Language historical toggle")
          if !compact { totals }
        }
        if compact { totals }
      }
      .frame(width: column + 40, alignment: .leading)
      .offset(x: column + 128, y: compact ? 12 : 20)
      WorkbenchStyle.hairline.frame(width: width - 48, height: 1).offset(x: 24, y: 76)
    }
    .frame(height: 77)
    .font(.system(size: 13))
    .onChange(of: browser.filter.minimumSpeakers) {
      threshold = SpeakerThreshold.format(browser.filter.minimumSpeakers)
    }
  }

  private var slider: some View {
    VStack(spacing: 0) {
      Slider(
        value: Binding(
          get: { SpeakerThreshold.position(browser.filter.minimumSpeakers) },
          set: { browser.filter.minimumSpeakers = SpeakerThreshold.value($0) }),
        in: 0...SpeakerThreshold.position(browser.maximumSpeakers)
      )
      .frame(height: 24)
      .accessibilityLabel("Language speaker threshold")
      .accessibilityIdentifier("Language speaker slider")
      .help("Logarithmic scale; All removes the speaker cutoff")
      GeometryReader { geometry in
        let ticks = Array(
          Set([
            0, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000,
            browser.maximumSpeakers,
          ])
        ).sorted()
        ForEach(ticks.filter { $0 <= browser.maximumSpeakers }, id: \.self) { value in
          Text(verbatim: SpeakerThreshold.format(value))
            .font(.system(size: 11)).foregroundStyle(WorkbenchStyle.secondaryInk)
            .fixedSize()
            .position(
              x: 7 + (geometry.size.width - 14) * SpeakerThreshold.position(value)
                / SpeakerThreshold.position(browser.maximumSpeakers),
              y: 7)
        }
      }.frame(height: 16)
    }
  }

  private var speakerField: some View {
    TextField("Minimum speaker count", text: $threshold)
      .textFieldStyle(.plain)
      .monospacedDigit()
      .overlay(alignment: .bottom) { WorkbenchStyle.fieldUnderline.frame(height: 1) }
      .accessibilityLabel("Minimum language speakers")
      .accessibilityIdentifier("Language speaker field")
      .onSubmit {
        if let value = SpeakerThreshold.parse(threshold) {
          browser.filter.minimumSpeakers = min(value, browser.maximumSpeakers)
        }
        threshold = SpeakerThreshold.format(browser.filter.minimumSpeakers)
      }
      .help("Enter All or a count such as 100k or 8.3M; the catalog's largest count is the limit")
  }

  private var coverage: some View {
    HStack(spacing: 6) {
      Text("Coverage").foregroundStyle(WorkbenchStyle.secondaryInk)
      Picker("Language coverage", selection: $browser.coverageFilter) {
        ForEach(LanguageCoverageFilter.options(comparing: comparing), id: \.self) {
          Text(verbatim: $0.rawValue).tag($0)
        }
      }.labelsHidden().pickerStyle(.menu)
        .accessibilityIdentifier("Language coverage picker").fixedSize()
    }
  }

  private var totals: some View {
    HStack(spacing: 8) {
      Spacer(minLength: 0)
      if browser.checking {
        ProgressView().controlSize(.small).accessibilityLabel("Checking language coverage")
      }
      Text(verbatim: "\(browser.rows.count) languages").foregroundStyle(WorkbenchStyle.secondaryInk)
        .fixedSize()
      Button("Clear Filters", action: browser.clearFilters)
        .accessibilityIdentifier("Language clear filters button")
        .fixedSize()
    }.frame(height: 24)
  }
}

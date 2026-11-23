<!--
Copyright © 2026 Michael Shields

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# Specimen highlight benchmark

Run `make benchmark-highlights` on an unlocked desktop with the fuzzer's
Accessibility and event-posting permissions enabled. It builds the optimized
FuzzBenchmark app, replays the
[saved trace](../scripts/benchmarks/highlights/100k.json) in seven fresh
processes, and prints per-action median milliseconds. The summary and per-run
telemetry go in `.build/highlight-benchmark/`. The target fails unless all
repetitions succeed.

The fixture preserves the exact 100,000 UTF-16-unit specimen from VM finding
`00002348-f603ab1e4d4c79cf`, whose first Shape press took 1,878.6 ms. It
includes ligatures, combining accents, missing emoji, and paragraph breaks. The
benchmark opens the editor with its button, sets the text, and waits three
seconds after Apply before toggling Shape off/on, Spacing on/off, and Frequency
off/on. Each toggle has 200 ms of pacing afterward. Both specimens are visible,
with the default Helvetica Neue and Arial configurations and the viewport at the
top.

The fuzzer measures control resolution plus accessibility action dispatch. Fixed
pacing, startup, shutdown, and final asynchronous completion are excluded from
each action's timing. This measures UI action latency, including harness
overhead. The three-second setup pause separates highlight updates from initial
text loading, so these timings are not directly comparable to the original VM
finding.

## Results

Measured on 2026-10-02 on an Apple M1 Max with 64 GiB RAM, macOS 27.0.1
(26A434). Both apps use the same FuzzBenchmark configuration, without coverage
instrumentation, and the same driver and trace. The baseline is commit
`7ffd949`; the viewport implementation is the code accompanying this benchmark.
Both sets have seven successful repetitions and zero failed repetitions.

| Action        | Baseline median | Viewport median | Reduction |
| ------------- | --------------: | --------------: | --------: |
| Shape off     |        308.8 ms |        202.2 ms |     34.5% |
| Shape on      |        481.4 ms |        175.9 ms |     63.5% |
| Spacing on    |        622.7 ms |        187.4 ms |     69.9% |
| Spacing off   |        473.8 ms |        167.7 ms |     64.6% |
| Frequency off |        358.3 ms |        181.6 ms |     49.3% |
| Frequency on  |        343.0 ms |        171.5 ms |     50.0% |

The complete summaries, including setup timings, are checked in as
[baseline](benchmarks/highlights-baseline.json) and
[viewport](benchmarks/highlights-viewport.json).

## Comparing revisions

Build the other revision with `make fuzz-build` in its own worktree. From the
worktree containing this benchmark, run:

```sh
make benchmark-highlights \
  HIGHLIGHT_APP=/path/to/baseline/.build/fuzz-benchmark/FuzzBenchmark/TypefaceOff.app \
  HIGHLIGHT_OUTPUT=.build/highlight-benchmark-baseline
make benchmark-highlights HIGHLIGHT_OUTPUT=.build/highlight-benchmark-viewport
```

`HIGHLIGHT_RUNS` changes the repetition count. Keep the machine, window
geometry, font installation, driver, trace, and repetition count the same for
both revisions. Run them sequentially without other app tests or benchmarks
competing for the desktop. The summary indexes correspond to the trace's
actions; indexes three through eight are the highlight toggles.

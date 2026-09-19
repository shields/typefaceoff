/* Geometric glyph comparison. No font-specific examples or curated rankings. */
"use strict";

window.GlyphDifferences = (() => {
  const REFERENCE_EM = 192;
  const canvases = [
    document.createElement("canvas"),
    document.createElement("canvas"),
  ];

  // Antialiased intersection over union: zero for identical ink, one for no overlap.
  function inkDifference(a, b) {
    let intersection = 0,
      union = 0;
    for (let i = 3; i < a.length; i += 4) {
      intersection += Math.min(a[i], b[i]);
      union += Math.max(a[i], b[i]);
    }
    return union ? 1 - intersection / union : 0;
  }

  function compare(char, a, b, { measure, family }) {
    const configs = [a, b];
    let sizes = [REFERENCE_EM, (REFERENCE_EM * b.size) / a.size];
    // Shape excludes added tracking. Spacing includes it explicitly in the advance.
    const untracked = configs.map((c) => ({ ...c, tracking: 0 }));
    const metrics = untracked.map((c, i) => measure(c, char, sizes[i]));
    const advances = metrics.map(
      (m, i) => m.advance + configs[i].tracking * sizes[i],
    );
    const bearings = metrics.map((m) => [m.x, m.advance - m.x - m.width]);
    const spacing =
      (Math.abs(advances[0] - advances[1]) +
        Math.abs(bearings[0][0] - bearings[1][0]) +
        Math.abs(bearings[0][1] - bearings[1][1])) /
      (3 * REFERENCE_EM);

    // Both glyphs share a baseline and left ink edge. Keep their relative sizes;
    // never stretch an individual glyph to make its bounding box match the other.
    const ascent = Math.max(...metrics.map((m) => -m.y), 0);
    const descent = Math.max(...metrics.map((m) => m.y + m.height), 0);
    const width = Math.max(...metrics.map((m) => m.width), 1);
    const height = Math.max(ascent + descent, 1);
    const fit = Math.min(1, 504 / Math.max(width, height));
    const baseline = 4 + ascent * fit;
    sizes = sizes.map((size) => size * fit);
    const pixels = canvases.map((canvas, i) => {
      canvas.width = Math.ceil(width * fit) + 8;
      canvas.height = Math.ceil(height * fit) + 8;
      const ctx = canvas.getContext("2d", { willReadFrequently: true });
      ctx.font = `${configs[i].axes.wght ?? 400} ${sizes[i]}px "${family(configs[i])}"`;
      ctx.fontKerning = configs[i].features.kern === 0 ? "none" : "normal";
      ctx.letterSpacing = "0px";
      ctx.fillStyle = "#fff";
      ctx.fillText(char, 4 - metrics[i].x * fit, baseline);
      return ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    });
    return { char, shape: inkDifference(...pixels), spacing };
  }

  function rank(scores, enabled) {
    const metrics = ["shape", "spacing"].filter((key) => enabled[key]);
    if (!metrics.length) metrics.push("shape", "spacing");
    // Percentiles give shape and spacing equal influence without mixing % and em.
    // Average ranks preserve ties (including the all-zero, identical-font case).
    const percentiles = {};
    for (const key of metrics) {
      const sorted = [...scores].sort((a, b) => a[key] - b[key]);
      percentiles[key] = new Map();
      for (let i = 0; i < sorted.length;) {
        let end = i + 1;
        while (
          end < sorted.length &&
          Math.abs(sorted[end][key] - sorted[i][key]) < 1e-9
        )
          end++;
        const percentile =
          sorted[i][key] > 1e-9
            ? (i + end - 1) / 2 / Math.max(1, sorted.length - 1)
            : 0;
        for (let j = i; j < end; j++)
          percentiles[key].set(sorted[j].char, percentile);
        i = end;
      }
    }
    return scores
      .map((item) => ({
        ...item,
        score:
          metrics.length === 1
            ? item[metrics[0]]
            : metrics.reduce(
                (sum, key) => sum + percentiles[key].get(item.char),
                0,
              ) / metrics.length,
      }))
      .sort(
        (a, b) =>
          b.score - a.score || a.char.codePointAt(0) - b.char.codePointAt(0),
      );
  }

  return { compare, rank, inkDifference };
})();

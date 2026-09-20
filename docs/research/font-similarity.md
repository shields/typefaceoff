**Font similarity and option fitting — research assessment, September 20, 2026**

The strongest next experiment is a comparison between a small learned font
metric, font-specific image embeddings, and a native rendering loss combining
distance fields, multiple blur scales, and shaped-text metrics. No source
reviewed establishes a ready-made winner for both of Typeface/Off’s tasks. The
recommendations below are an experimental design; no new model or optimizer was
benchmarked in the app during this research.

**Define the two tasks separately.**

| Task               | Fixed inputs                                                             | What varies                                                                       | Desired result                                                      |
| ------------------ | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Rank default fonts | Text corpus, point size, renderer, display scale, default-setting policy | Font identity                                                                     | Fonts whose actual displayed appearance is closest to the reference |
| Fit font B         | Font A and its selected settings, B’s family, text corpus, user locks    | B’s supported axes, feature choices, tracking, and optionally size or static face | A legal B configuration whose rendered appearance is closer to A    |

For the proposed first implementation, keep point size fixed during fitting and
offer size matching separately. This is an assumption pending product
preference. Default-font ranking must never silently optimize the candidates
first: similarity at defaults and similarity after fitting are different
results.

The objective needs to preserve apparent size, width, weight, slant, and
spacing. Independent bounding-box normalization would erase some of the
requested signal. Likewise, finding fonts that pair attractively with A is a
different problem from finding fonts that resemble A.

**The most relevant published evidence.**

| Method                                                           | What the evidence establishes                                                                                                                                                                                                                                                                                                                   | Assessment for this app                                                                                                                                                                                                                                                                 |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Learned geometric/attribute metric, O’Donovan et al. (2014)      | Learns a small embedding from human font comparisons. Its attribute subspace predicts 75.83% of individual judgments with leave-one-font-out validation; an oracle choosing the majority response reaches 80.79%.                                                                                                                               | A serious lightweight baseline. It demonstrates that learning which differences matter can be valuable without a large image model. [Paper, §5](https://www.dgp.toronto.edu/~donovan/font/fontSelection.pdf#page=5)                                                                     |
| FontCLIP (2024)                                                  | Reports 74.39% on pairwise font similarity, versus 67.68% for original CLIP and 75.95% for the earlier feature-based method. Its similarity evaluation uses the complete 200-font dataset; the separate attribute-prediction split does not make this a held-out-font similarity result.                                                        | Strong learned style candidate, especially for broader script coverage. The published comparison does not establish superiority over the smaller learned metric or validate equal-point-size behavior. [Paper, §6](https://jdily.github.io/resource/fontclip/fontCLIP_paper.pdf#page=6) |
| Distance-transform-weighted pseudo-Hamming, Uchida et al. (2015) | Studies 7,000 fonts. It combines mismatch area with distance to the other glyph’s foreground, addressing limitations of both pixel mismatch and contour-only distance. The evaluation is not a controlled human ranking study.                                                                                                                  | Directly relevant, inexpensive geometric baseline. [Paper, §IV](https://human.ait.kyushu-u.ac.jp/publications/ICDAR2015-Uchida.pdf#page=3)                                                                                                                                              |
| SSIM, Takizawa et al. (2020)                                     | Includes 500 respondents comparing five fonts using alphanumeric specimens. Results favor SSIM-related comparisons but depend on resolution and character selection. A later 200-font experiment uses SSIM as its reference, rather than new human judgments. One ambiguous human aggregate ranking was resolved partly by algorithm agreement. | Worth benchmarking; evidence is too narrow to designate SSIM the perceptual solution. [Paper, §§4–5](https://www.jstage.jst.go.jp/article/ijae/19/2/19_IJAE-D-19-00012/_pdf/-char/ja#page=4)                                                                                            |
| Differentiable Variable Fonts, Parikh et al. (2026)              | Differentiates variable-font interpolation and rasterization, then fits axes with image squared error and Adam. Examples include approximating a Didot glyph with Amstelvar Roman.                                                                                                                                                              | Direct evidence that axis fitting is feasible, but its objective is not a human-validated font similarity model. [Paper](https://onlinelibrary.wiley.com/doi/10.1111/cgf.70415)                                                                                                         |

The percentages above should not be combined into a leaderboard with a common
test protocol. In particular, identifying the correct font in a photograph,
predicting a majority preference, and predicting an individual person’s response
are distinct evaluations.

The original 2014 supplement documents **2,340 distinct triplets and 35,387
individual comparisons**. It compares unweighted, weighted, and learned-subspace
distances on geometric features and predicted attributes. The distinction
between triplets and responses matters when designing splits and confidence
intervals. The author page publishes similarity data and MATLAB learning code;
the archive contents and their license were not inspected here because the
download was unavailable through the research environment.
[Supplement](https://www.dgp.toronto.edu/~donovan/font/supplemental.pdf#page=6),
[project and downloads](https://www.dgp.toronto.edu/~donovan/font/).

**Learned models that are actually available.**

| Candidate                               | Available artifact                                                                                                                         | Material limitation                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FontCLIP                                | Official code and a Google Drive checkpoint link in `setup_data.py`; main code has an MIT license with exceptions for separate components. | Checkpoint-license scope is unresolved in an open issue. Its inference pipeline averages embeddings from rotated/resized crops, so physical-size sensitivity needs testing. [Code](https://github.com/yukistavailable/FontCLIP), [setup](https://github.com/yukistavailable/FontCLIP/blob/main/setup_data.py), [transforms](https://github.com/yukistavailable/FontCLIP/blob/main/utils/transform_image.py), [checkpoint issue](https://github.com/yukistavailable/FontCLIP/issues/13) |
| Storia Google Font Classifier           | A released EfficientNet-B3 ONNX model, approximately 64 MB, with MIT model metadata.                                                       | A recognition model. ControlText’s use of classifier-probability distances explicitly assumes they express font similarity; the cited work does not independently validate agreement with human rankings. [Model](https://huggingface.co/storia/font-classify-onnx), [ControlText, §3.4.2](https://arxiv.org/html/2502.10999v2#S3.SS4.SSS2)                                                                                                                                            |
| GoogleFontsBench / DINOv2 + LoRA (2026) | Public 87.2-million-parameter model with Apache-2.0 metadata.                                                                              | Its severity-weighted error uses its own embedding distances, which cannot independently validate perceptual agreement. Producer artifacts also differ in some reported benchmark details. [Paper](https://arxiv.org/html/2602.13889v1), [weights](https://huggingface.co/dchen0/font_classifier_v4), [code](https://github.com/Create-Inc/font-model)                                                                                                                                 |
| FontVLM (2026)                          | Official training code and reference-library recognition workflow.                                                                         | Its task is recognition of unseen fonts. A released trained FontVLM checkpoint was not verified; backbone downloads are not that checkpoint. [Code](https://github.com/Tunanzzz/FontVLM), [paper](https://openaccess.thecvf.com/content/CVPR2026F/html/Zhou_Towards_Universal_Open-Set_Visual_Font_Recognition_Via_Augmented_Synthetic_Similarity_CVPRF_2026_paper.html)                                                                                                               |
| DeepFont (2015)                         | Published architecture and feature-averaging method.                                                                                       | The paper explicitly says its font-similarity results were not numerically verified. Its recognition accuracy is not perceptual accuracy. An official usable checkpoint was not verified. [Paper, §5.4](https://arxiv.org/pdf/1507.03196#page=8)                                                                                                                                                                                                                                       |

Start learned-model experiments with FontCLIP if its checkpoint terms are
resolved, and Storia as an accessible technical challenger. Test intermediate
embeddings and classifier-output distances separately. A representation
optimized to distinguish named classes need not provide a smooth measure of
small changes within one variable font. This is a hypothesis to test, not a
measured defect in either model.

**General image metrics are useful controls, with different invariances.**

| Metric         | Reason to include or deprioritize it                                                                                                                                                                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SSIM / MS-SSIM | Inexpensive structural baselines. Multiscale comparison explicitly addresses viewing scale, but its original validation concerns image quality rather than font substitution. [MS-SSIM paper](https://live.ece.utexas.edu/publications/2003/zw_asil2003_msssim.pdf)             |
| CW-SSIM        | Discounts small geometric transformations. That can hide width, slant, or displacement changes the fitter should measure. Lower priority for this task. [Authors’ paper page](https://www.ece.uwaterloo.ca/~z70wang/publications/icassp05.html)                                 |
| LPIPS          | Strong precedent for learning from human image judgments, but its original benchmark is image distortions and processing outputs, not font similarity. [Paper and implementation](https://richzhang.github.io/PerceptualSimilarity/)                                            |
| DISTS          | Deliberately tolerates texture resampling; its geometric experiments assume unchanged quality after some shifts, rotations, and dilation. Useful as a texture challenger, questionable as the sole fitting loss. [Paper, §§II-D and III-F](https://arxiv.org/html/2004.07728v2) |
| DreamSim       | Learns human similarity from synthetic image triplets; the authors identify object-centric coverage as a limitation. Font-specific encoders deserve higher priority here. [Paper, Appendix C](https://arxiv.org/html/2306.09344v3)                                              |

A Gaussian pyramid of glyph/text masks is another inexpensive candidate. Blurred
font discrimination has some psychophysical support, but does not validate a
particular weighted blur loss. Keep a fine-detail channel so that accents,
counters, terminals, and thin strokes remain consequential.
[Morris and Legge abstract](https://opg.optica.org/abstract.cfm?uri=OAM-1992-ThVV5).

**Proposed rendering contract.**

Use Core Text for every score that is meant to predict the app’s displayed
result. Render identical content at the actual requested point size and display
scale, with a common baseline and origin. Preserve the requested instance when
producing supersampled images; increasing raster resolution must not
inadvertently select a different optical-size design.

Define “default” explicitly: family/face selection, variation coordinates,
tracking, language/script, automatic shaping, and optical-size policy. OpenType
defines per-axis default coordinates, while automatic optical-size selection can
depend on text size and viewing conditions. Cache the effective configuration;
do not silently equate font-table defaults with every platform’s rendering
defaults.
[Axis defaults](https://learn.microsoft.com/en-us/typography/opentype/spec/fvar),
[optical-size specification](https://learn.microsoft.com/en-us/typography/opentype/spec/dvaraxistag_opsz).

Use a fixed diagnostic corpus for general rankings and a clearly identified
sample-dependent mode when using the user’s text. Include lowercase, uppercase,
numbers, punctuation, diacritics, spaces, and short sequences exercising
kerning, ligatures, and contextual alternatives. Select corpora by script. Do
not improve a font’s apparent score by silently dropping the characters it
cannot render: report coverage explicitly and exclude ineligible candidates from
a full-coverage ranking.

Keep isolated glyph comparisons and short shaped strings. A long paragraph
compared pixel-for-pixel from its origin can accumulate minor spacing
differences until later letters no longer align, overwhelming useful local
information. Short word samples plus explicit advance measurements make this
tradeoff easier to control. Preserve the app’s independent shape and spacing
views even if a separate aggregate score is introduced.

**Proposed loss to benchmark.**

```text
distance(A, B) =
    wg × mean glyph distance-field error
  + wa × mean glyph multiscale mask error
  + wr × mean short shaped-run appearance error
  + wm × advance/space/vertical-metric error in fixed units
  + we × optional learned font-embedding distance
```

This decomposition is a proposal. Select weights using human data; initially
benchmark the components individually as well as combinations. Do not transplant
the current percentile-rank combination into this objective. The score must
retain magnitude and must not change when unrelated catalog entries are added.

For geometry, compare the published pseudo-Hamming distance with truncated
signed distance fields. A signed field preserves the distinction between ink and
holes; truncation limits the influence of empty exterior space. Efficient
sampled Euclidean distance transforms have a linear-time algorithm.
[Felzenszwalb and Huttenlocher](https://theoryofcomputing.org/articles/v008a019/).

Use fixed, sufficiently large canvases and deliberate pooling so matching white
background does not dominate. Test invariance to additional identical padding.
Do not discard interior white counters as “background.” Avoid freely
translating, rotating, or scaling one font to reduce loss unless that
transformation is an explicitly enabled fitting option. If using an ink-aligned
shape channel, retain a separate origin-aligned layout channel.

For catalog search, cached embeddings or compact geometric descriptors can
retrieve a shortlist, then the actual-size loss can rerank it. Measure shortlist
recall against a full comparison before making this an optimization; a shortlist
must not systematically discard the best visual matches. For a small catalog,
direct cached scoring may be simpler.

**The discrete/continuous search proposal is sound, with constraints.**

Adobe’s ATypI 2020 presentation describes using DeepFont similarity, selecting
relevant axes, and greedily finding a matching instance of B. It supplies useful
prior art, but the accessible abstract does not provide convincing perceptual or
runtime benchmarks.
[Presentation](https://atypi.org/presentation/efficient-methodology-to-detect-similar-instance-of-variable-font/).

Use a bounded multistart pattern search as the first native implementation.
Compare it with Powell direction-set search under the same evaluation budget.
BOBYQA is a candidate for smoother objectives; its documentation cautions about
losses that are not twice differentiable. CMA-ES is a reasonable longer-running
challenger for coupled axes. These are engineering choices, not established font
benchmark winners.
[Powell](https://docs.scipy.org/doc/scipy/reference/optimize.minimize-powell.html),
[BOBYQA](https://nlopt.readthedocs.io/en/latest/NLopt_Algorithms/#bobyqa),
[CMA-ES](https://cma-es.github.io/).

Features require a constrained categorical domain: some are exclusive, some
character variants have several values, and identically numbered variant tags in
different fonts need not represent equivalent shapes. Preserve required script
shaping and user locks. Evaluate rendered results rather than copying feature
numbers from A.
[OpenType character variants](https://learn.microsoft.com/en-us/typography/opentype/spec/features_ae#tag-cv01--cv99),
[Core Text feature settings](https://developer.apple.com/documentation/coretext/kctfontfeaturesettingsattribute).

Scale optimization coordinates by their legal ranges while leaving actual
interpolation to Core Text. Axis responses can be nonuniform because of `avar`,
axes can interact through variation interpolation, and FeatureVariations can
change substitutions or positioning at region boundaries. Reshape each
candidate; do not assume a globally smooth objective.
[Variation overview](https://learn.microsoft.com/en-us/typography/opentype/spec/otvaroverview),
[`avar`](https://learn.microsoft.com/en-us/typography/opentype/spec/avar),
[FeatureVariations](https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2#feature-variations).

```text
render target A once for the search corpus
build B’s legal domains, respecting user locks
seed from B’s current/default settings, named instances, and sparse axis samples

if the categorical domain is small:
    enumerate valid feature combinations
    optimize continuous settings from several seeds for each combination
else:
    keep a small beam of distinct good states
    alternate bounded continuous search and valid categorical neighbors
    include selected paired feature changes and joint axis directions
    refine promising feature alternatives before rejecting them

rerank finalists on the full corpus at the actual display resolution
return the best result, alternatives, and improvement over the starting B
```

Enumerating every valid feature combination does not make the continuous search
globally optimal. Likewise, a feature inert at defaults can become active in
another combination or axis region. Deduplicate evaluated shaping/rendering
results, but do not permanently prune a feature based on a single toggle probe.

Tracking can sometimes be fitted cheaply from shaped-run advances as a warm
start. Keep the current measured approach’s attention to the zero-tracking
ligature boundary. An analytic fit for a fixed shaping regime is not necessarily
the minimum of the full image objective. Existing x-height and numeric-weight
matching are also useful initial guesses rather than final perceptual answers.

Cache target masks, distance fields, embeddings, and measurements. Use a smaller
diagnostic corpus during search and validate finalists on held-out strings.
Warm-start when A changes, cancel obsolete requests, and expose progressive
improvement under a time/evaluation budget. Native runtime remains unmeasured.

**Differentiation is promising, but currently a larger integration project.**

The 2026 differentiable-font paper uses 100 Adam iterations. Its reported M1 Pro
CPU times imply approximately 37–221 seconds for the single-glyph example fits,
by multiplying per-iteration costs; this is not a measured Typeface/Off latency.
The framework does not handle discrete substitutions and leaves full shaping
outside its scope. Its small user study evaluates manipulation rather than
similarity. An official font implementation was not verified from the
author/publication pages; the underlying diffvg renderer is available.
[Paper, §§5–6](https://onlinelibrary.wiley.com/doi/10.1111/cgf.70415),
[diffvg](https://github.com/BachiLi/diffvg).

A future differentiable backend could generate promising axis settings and then
verify them through Core Text. It should not replace the renderer used for final
scoring until shaping, rasterization, and feature parity are established.

**Validation should decide which approach ships.**

Run two separate evaluations:

1. **Does the metric match people?** Collect blinded triplets asking whether B
   or C looks closer to A at a stated size, and direct preferences between
   fitted configurations. Include near-neighbor families, equal-size x-height
   differences, similar weights, `a`/`g` construction, accents, apertures,
   ligatures, spacing, and scripts supported by the app. Include ties and
   repeated judgments.
2. **Does the optimizer find good settings under that metric?** Generate targets
   from known settings, recover a visually equivalent result, compare small
   parameter spaces with a dense reference grid, and compare solvers at equal
   render/evaluation budgets. Parameter recovery is not always unique: multiple
   settings may produce indistinguishable output on the selected text.

Split by family and hold out text, sizes, and settings. Random image splits can
leak nearly identical family members. Measure individual-vote agreement and
majority agreement separately, report uncertainty and human disagreement, and
check top-ranked candidates rather than only easy serif-versus-sans
distinctions. For fitting, report improvement over defaults and the existing
matcher, full-text generalization, failures, and runtime. A lower loss alone is
not a perceptual win.

Use the published human dataset to reproduce its original benchmark conditions.
Re-rendering the fonts at different sizes or with different specimens does not
guarantee that those judgments remain applicable; collect new judgments for our
actual display conditions.

First benchmark the existing overlap score, distance fields, multiscale masks,
SSIM/MS-SSIM, and their small learned combinations. Add the available font
encoders as challengers, then assess whether their added accuracy justifies the
model footprint and inference cost. Keep a separate validation set untouched
while choosing weights and search budgets.

**Implementation references and research limits.**

Useful reference implementations include
[TinySDF](https://github.com/mapbox/tiny-sdf) (BSD-2-Clause),
[pytorch-msssim](https://github.com/VainF/pytorch-msssim) (MIT),
[LPIPS](https://github.com/richzhang/PerceptualSimilarity) (BSD-2-Clause),
[DISTS](https://github.com/dingkeyan93/DISTS) (MIT), and
[DreamSim](https://github.com/ssundaram21/dreamsim) (MIT). These describe
repository code licenses; model artifacts and backbones have their own
provenance.

Research covered primary papers, author pages, specifications, repositories, and
model cards through September 20, 2026, including forward searches for newer
recognition and font-embedding work. Remaining gaps are equal-point-size human
validation, small-settings sensitivity of available encoders, native
performance, and some checkpoint/data availability or terms. No model was
downloaded or run, and no app implementation changed.

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

# Character frequencies

This is the research record behind frequency weighting: why it uses a global,
speaker-weighted mix of languages, which languages the mix includes, which
weighting formula was chosen and why, and what the result still gets wrong. The
README’s “Character frequencies” section describes the feature and how to
regenerate its data; NOTICE credits the sources.

## Why a global, speaker-weighted mix

[FineFreq](https://huggingface.co/datasets/lgi2p/finefreq) (Xu,
[arXiv:2512.09701](https://arxiv.org/abs/2512.09701)) counts characters per
language. Its English table comes from FineWeb, a crawl far larger than the
FineWeb2 data behind every other language, so English is 84% of all the
characters it counts. Summing the tables would reproduce the English table.

Instead, each language’s table is normalized to shares of its non-whitespace
characters, and the shares are mixed in proportion to the language’s speakers
(L1 + L2, or L1 alone for Greek and Polish). English then carries 18.71% of the
mix.

## Languages

The mix uses the top 40 languages by total speakers in Ethnologue’s 29th edition
(2026). Four of them have no FineFreq table: Hausa (rank 20, 94.5M speakers),
Sudanese Arabic (36, 54.3M), Jinyu Chinese (39, 48.0M), and Min Nan Chinese (40,
45.8M), together 3.0% of the top 40’s speakers. Greek, Hebrew, and Polish rank
below the top 40 but are added so that their common letters are ranked rather
than left at the floor; their speakers are Ethnologue’s 22nd edition (2019)
figures as recorded in Wikidata, first-language only for Greek and Polish. The
39 languages’ weights are normalized to sum to 1:

| Rank | Language         | Speakers | Weight |
| ---: | ---------------- | -------: | -----: |
|    1 | English          | 1,493.0M | 18.71% |
|    2 | Mandarin Chinese | 1,183.0M | 14.83% |
|    3 | Hindi            |   611.2M |  7.66% |
|    4 | Spanish          |   561.3M |  7.03% |
|    5 | Standard Arabic  |   334.9M |  4.20% |
|    6 | French           |   333.5M |  4.18% |
|    7 | Bengali          |   274.4M |  3.44% |
|    8 | Portuguese       |   269.4M |  3.38% |
|    9 | Indonesian       |   254.8M |  3.19% |
|   10 | Urdu             |   246.0M |  3.08% |
|   11 | Russian          |   210.3M |  2.64% |
|   12 | Standard German  |   133.4M |  1.67% |
|   13 | Japanese         |   125.7M |  1.58% |
|   14 | Nigerian Pidgin  |   120.7M |  1.51% |
|   15 | Egyptian Arabic  |   118.4M |  1.48% |
|   16 | Marathi          |    99.2M |  1.24% |
|   17 | Vietnamese       |    97.1M |  1.22% |
|   18 | Telugu           |    95.9M |  1.20% |
|   19 | Swahili          |    95.2M |  1.19% |
|   21 | Turkish          |    93.7M |  1.17% |
|   22 | Western Punjabi  |    90.4M |  1.13% |
|   23 | Tagalog          |    87.1M |  1.09% |
|   24 | Tamil            |    86.4M |  1.08% |
|   25 | Yue Chinese      |    85.8M |  1.08% |
|   26 | Wu Chinese       |    83.3M |  1.04% |
|   27 | Iranian Persian  |    82.5M |  1.03% |
|   28 | Korean           |    82.2M |  1.03% |
|   29 | Amharic          |    78.0M |  0.98% |
|   30 | Thai             |    71.4M |  0.89% |
|   31 | Javanese         |    69.2M |  0.87% |
|   32 | Italian          |    65.6M |  0.82% |
|   33 | Gujarati         |    62.5M |  0.78% |
|   34 | Kannada          |    58.7M |  0.74% |
|   35 | Levantine Arabic |    57.8M |  0.72% |
|   37 | Yoruba           |    52.9M |  0.66% |
|   38 | Bhojpuri         |    52.7M |  0.66% |
|    — | Polish           |    39.7M |  0.50% |
|    — | Greek            |    13.1M |  0.16% |
|    — | Hebrew           |     9.3M |  0.12% |

Several languages have more than one FineFreq table, such as Hindi in Devanagari
and in romanized Latin; a language’s weight is split among its tables in
proportion to the characters each counted.

## Characters that NFKC removed

FineFreq applied NFKC normalization before counting, so compatibility characters
such as …, ½, ™, ﬁ, Thai ำ, and CJK fullwidth punctuation (，！？（）) have no
counts, and each occurrence was counted as its expansion instead: … as three
periods, ， as a comma. Following the approach of
[raycast-charp](https://github.com/shields/raycast-charp), each language’s
characters are also counted in a non-normalized
[Leipzig Corpora Collection](https://wortschatz.uni-leipzig.de) corpus, and a
least-squares fit of log FineFreq share against log Leipzig share, over
characters both sources count, projects the missing characters onto FineFreq’s
scale. Each estimate is then subtracted from the characters it expands to. In
the global mix this lowers the comma by 11%, parentheses by 19%, and the
semicolon by half, and gives fullwidth punctuation, …, and ำ shares of their
own. Romanized tables keep FineFreq’s counts unchanged, because the only Leipzig
corpora for their languages are in the native script.

The generated table keeps the 2,979 characters with a share of at least 1e-5,
which together account for 98.7% of all characters.

## Choosing the weighting formula

Eight font pairs (Helvetica and Arial, Helvetica Neue and Avenir Next, Times New
Roman and Georgia, Palatino and Baskerville, Menlo and Courier, Futura and Gill
Sans, Helvetica and Helvetica Light, and Georgia and Charter) were scored on the
103 characters of the built-in samples. Each candidate weighting of the raw
difference `d` by global share `p` was compared by eye with each pair’s known
distinguishing characters and by rank correlation (Spearman’s ρ) with both the
unweighted ranking and a ranking by frequency alone.

| Weighting                    | Result                                                   |
| ---------------------------- | -------------------------------------------------------- |
| None                         | Thin marks such as `= _ ~ < >` lead every pair           |
| `d · p`                      | The same frequency order for every pair (ρ 0.94)         |
| `d · √p`                     | Still mostly frequency order (ρ 0.81)                    |
| `d · ∛p`                     | Frequency order for some pairs, thin marks for others    |
| `d ·` log-scaled `p`         | Nearly the unweighted order (ρ 0.86 with it)             |
| `d ·` frequency rank         | Frequency-led, and changes whenever the sample text does |
| `d · √(min(p, 10⁻³) / 10⁻³)` | Each pair’s own differences lead; rare symbols sink      |

Without weighting, the top of every list is thin or offset marks whose ink
barely overlaps between fonts, so their shape difference nears its maximum
whatever the design. Weighting by `p` or `√p` overcorrects: `p` spans four
orders of magnitude while differences span about one, so `e` outweighs `k` even
under a square root, and every pair shows the same list of common letters. A
logarithmic weight spans only about 2.5× over the candidates, too little to
offset thin marks.

The chosen weight is `w = √(min(p, 10⁻³) / 10⁻³)`. Characters that occur at
least once per thousand, which include every lowercase Latin letter, the common
capitals and digits, and `, . - :`, keep full weight and rank by their
difference alone, so each pair’s distinguishing characters rise: Georgia’s
old-style figures against Times, Gill Sans’s a, g, and M against Futura, and
Courier’s r and m against Menlo. Rarer characters are discounted by the square
root of how much rarer they are, so a symbol 100 times rarer needs a difference
10 times larger to compete. Shares below 10⁻⁵, including characters absent from
the table, count as 10⁻⁵, so no character is discounted more than tenfold.

Combined rankings sum each metric’s percentile rank and then multiply by `w`,
rather than weighting each metric before taking percentiles. That keeps every
full-weight character exactly in its unweighted order, and zero differences stay
at the bottom in every mode.

## Known limitations

- **Web text is not all text.** FineFreq counts web pages, and `|` in particular
  is inflated by navigation text such as “Home | About”, so it keeps a weight of
  about 0.7.
- **Smaller languages stay discounted.** Greek, Hebrew, and Polish together
  carry under 1% of the mix, so even their commonest letters, such as α, י, and
  ł, reach only about 10⁻⁴ and a weight near 0.3. Rarer letters such as Greek β,
  ζ, ξ, and ψ, Hebrew final ך, ף, and ץ, and Polish ź, as well as Greek and
  Polish capitals, fall below the floor. Characters of other languages outside
  the top 40 appear only incidentally and take the minimum weight. Turn
  Frequency off when comparing fonts for these languages, for code, or for the
  Numerals & punctuation sample.
- **The constants were tuned on eight pairs.** The 10⁻³ saturation point and
  10⁻⁵ floor sit on a broad plateau in that evaluation, but a very different
  pair could favor other values. Changing the shape metric would also call for
  retuning, since the weighting partly offsets how thin marks score.

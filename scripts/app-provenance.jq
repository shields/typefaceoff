def provenance($catalog; $frequencies):
  {
    hyperglot: ($catalog.version | select(type == "string" and length > 0) // error("Missing Hyperglot version")),
    source: ($catalog.source | select(. == "https://github.com/rosettatype/hyperglot") // error("Review the Hyperglot source and NOTICE")),
    finefreq: ($frequencies | capture("(?m)^# FineFreq .*pinned commit (?<sha>[a-f0-9]{40});").sha // error("Missing FineFreq commit")),
    wikipedia: ($frequencies | capture("(?m)^# Ethnologue: .*revision (?<id>[0-9]+)\\)").id // error("Missing Wikipedia revision"))
  };

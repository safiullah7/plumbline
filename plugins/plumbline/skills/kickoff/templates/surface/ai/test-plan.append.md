## Eval set
- Location: qa/evals/
- Size: number of cases, and how they were chosen
- Pass threshold: the score each metric must reach
- Golden set: cases with known good answers, kept fixed between runs
- Injection cases: inputs that try to override instructions or leak data
- Cost budget: maximum spend per full eval run
- Latency budget: p50 and p95 per call

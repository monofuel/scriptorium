## Engineering method

Before adding complexity (new parameters, workarounds, special cases, wrapper
layers), apply root cause analysis:

1. **Ask "why?" five times.** The first answer is a symptom. Dig until you find
   something structural. Fix the root cause, not the symptom.
2. **Follow the priority order: delete > simplify > optimize > add.** If a
   requirement is wrong, challenge it. If a part is unnecessary, remove it.
   Only add complexity after confirming the simpler options cannot work.
3. **Existing patterns are not automatically correct.** Code may contain
   workarounds that outlived their purpose. Question inherited complexity
   rather than building on top of it.

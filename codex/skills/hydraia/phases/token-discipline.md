## Token discipline (background, always on)

Internal reasoning and subagent instructions use the **caveman** compression style
to save tokens. This NEVER applies to code, commit messages, specs, plans, or the
final summary to the user — those stay clear and complete. It is purely a wording
style for internal comms; it is NOT a mandate to save tokens by skipping,
compressing, or inlining any phase. Phase completeness always wins over token
economy (see "No proportionality escape").

**Language + script lock (hard rule).** Compression changes the *style*, never the
*language or script*. Everything Hydraia emits — chapter titles, status lines,
sub-agent prompts, the summary — stays in the run's language chosen at the language
gate (English or Español) and in its native Latin script. **NEVER** switch to another
language or script to save characters. In particular the caveman `wenyan-ultra` level
(classical-Chinese-flavoured abbreviation) and any CJK/non-Latin ideograms are
FORBIDDEN in Hydraia output — they are denser per token but they corrupt the user's
reading experience (e.g. "探索"/"索引" leaking into chapter titles). Keep technical
terms, code, API names, and error strings verbatim as caveman already requires.

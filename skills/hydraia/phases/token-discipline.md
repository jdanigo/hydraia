## Token discipline (background, always on)

Internal reasoning and subagent instructions use the **caveman** compression style
to save tokens. This NEVER applies to code, commit messages, specs, plans, or the
final summary to the user — those stay clear and complete. It is purely a wording
style for internal comms; it is NOT a mandate to save tokens by skipping,
compressing, or inlining any phase. Phase completeness always wins over token
economy (see "No proportionality escape").

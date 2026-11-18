# Condensed message example (HFC Agent Skill)

Annotated example of the **condensed** message the agent drafts in A4 step 7 (and again after every "Process HFC feedback" pass, Pipeline B step 7), written to `hfc/config/summary_condensed.md`. It is the top of the parent report `hfc/outputs/<MMDD>_HFCs.html` (and the copy in the HFC Output Directory) and it is the message posted in chat. Below it the builder adds the Completion (overall, by enumerator, by date), Duplicates (only if any) and Form Version tables (Form Version only when there are form version issues, otherwise just "No form version issues found!"; the Completion card states how Completion is computed); those are generated, never written here. The long narrative (`assets/summary_message_example.md`) goes to the detailed report instead. Annotations in [brackets] are not part of the message.

The page's top-left title is always the hardcoded `HFC MM/DD` (the day it's generated), never the project name; the project name belongs in the opening line below.

Like the long narrative, this message reports on the **most recent day of data collection only**, with one exception: the cumulative completion figure in the opening paragraph.

---

> Hi @team, HFC update for the AI Extension pilot (Mubende), synced through Aug 17. 23 submissions on Aug 17 from 23 distinct farmers, 21 completed. Cumulative: 200 completed (170 primary, 30 replacements) against a primary-sample target of 329; 190 primary samples attempted (submitted), 105.3% completion.
>
> The 2 non-completions on Aug 17, both Joan Namakula: 1 failed "Manages a coffee farm," 1 failed "Has a functioning smartphone."
>
> Enumerators on Aug 17:
> - Amanya German: 4 submitted, 4 completed
> - Bridget Baseke: 4 submitted, 4 completed
> - Joan Namakula: 6 submitted, 4 completed
> - Nassali Mariah: 4 submitted, 4 completed
> - Wandera Benard: 5 submitted, 5 completed
>
> Issues to highlight:
> 1. 2 duplicates for Farmer 1042 (Amanya German), both submitted on Aug 17.
> 2. 3 interviews by Wandera Benard started after 8pm.
> 3. Form version mismatch on 2 submissions from Bridget Baseke (still on version 3).

[Paragraph 1, the opening: greeting, project name, sync date, that day's submissions (and distinct respondents) and completions, then the cumulative completion measured against the primary sample whenever one is known: completed (split primary / replacements), the primary-sample target, the primary samples attempted (submitted) and the resulting completion %, all from the build log's `Primary sample:` line (and M1's tables). Completion = completed ÷ primary samples attempted, so it can exceed 100% when replacements completed for primaries that never submitted. With no primary sample, say `N completed of M submitted (X%)`. Same facts as the long narrative's lead, in two or three sentences.]

[Paragraph 2: that day's non-completions only: count, who, and the specific reason each failed (the `gate_fail_reasons` text, M1's `stats$by_reason`). Omit the whole paragraph when nothing failed that day.]

[Enumerators: a bold label (rendered from the line `Enumerators on Aug 17:`) over a bullet list, one line per enumerator active that day, in the form `Name: N submitted, N completed`. Roster only: no call-outs for people who didn't submit.]

[Issues to highlight: a bold label over a numbered list of that day's most important findings, taken from `hfc/outputs/issues.csv`. Priority order: duplicates (M2), irregular timing (M5), field request (M9), form version (M3), numeric outliers (M6); anything else only when truly serious. List at least 2 and at most 5 whenever that day has issues; aim for about 3, and 5 is a cap, not a target. If that day has exactly 1 issue, list that one. Each item is one sentence with the real entity, enumerator and count. Only if that day has no issues at all, write a single plain line instead of the list: "Nothing to highlight on Aug 17."]

---

## What NOT to do

- Never "today", "yesterday" or a numeric date like 08/17. Name the last day of data collection (not the day the report is generated) as `Mon DD`, e.g. `Aug 17` or `May 09`, the same way everywhere. The builder warns when a message slips.
- No greeting variants that lose the project name or the "synced through <date>" part.
- No closing "N issues still open from earlier days" line. This message ends after the last issue.
- No sections, headings, tables, links or explanations of the tool in the message itself. Four spaced blocks and nothing else (the report adds its own tables below).
- Never leave the issues list out, or under 2 items, when that day has issues. Don't pad it to reach 5. Don't restate findings from earlier days. Don't invent detail the findings don't contain.
- Don't mention the pipeline, the checks that ran, or how the message was produced.
- Use real bullets (`-`) for the enumerators and real numbers (`1.`, `2.`) for the issues, each preceded by its label line ending in a colon, so the report renders bold labels and real lists.

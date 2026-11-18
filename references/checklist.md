# Package checklist

Use after Pipeline A (setup) and again after Pipeline B (post-feedback).

## Always required (setup)

| Item | Required |
|---|---|
| Microdata in the configured Input Data Directory (immutable) | yes |
| Instrument / form (also in the Input Data Directory) | optional (preferred for M9 / M3 / nested skip-logic) |
| Project description / Pre-Analysis Plan (pdf/doc/docx/txt/md, also in the Input Data Directory) | optional (read once for background context; never a data source) |
| `hfc/structure.html` opened *before* the report at the final Review & Approve gate (first-ever setup only — a rebuild opens only the report) | yes |
| Roster present: primary/replacement column confirmed (or the user said there is none: `M1.roster_all_primary: true`), and any submitted IDs missing from the roster resolved by the user (`M1.offroster_handling`) — never assumed | yes (build stops with `NEEDS_USER_INPUT:` otherwise) |
| Setup window (A1) — Gates 2-3: data found (always incl. the sample roster line, or "No sample roster found" + the question whether one exists), Instructions (incl. any specific-check requests) confirmed | yes |
| Completion Signal window (A1) — Gate 4: gate question(s)/reasons or roster/primary-secondary confirmed, if a signal was detected | yes |
| Entity/Group/Enumerator/timing/GPS/media/consent columns, Country, and every A2 module setting decided silently, from the agent's own reading of the data profile (no confirmation by default) | yes (reviewable via "Walk me through all modules" at Review & Approve) |
| Review & Approve window (A4) — final gate: approved before the live `issue_tracking.xlsx` is written | yes |
| `hfc/project.yaml` | yes |
| `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` | yes (agent writes from confirmed options before build) |
| `hfc/code/main.R` (one path global) | yes |
| `hfc/code/checks/` modules (real, runnable per-module scripts + custom), plus `main.R` running all of them in one call | yes |
| `hfc/config/summary_message.md` (long narrative) and `hfc/config/summary_condensed.md` (short message, also posted in chat), both naming the last day of data collection as `Mon DD` | yes (agent-drafted in A4 step 7) |
| `hfc/outputs/issues.csv` with stable, content-derived `finding_id` (Issue ID) | yes |
| Live `issue_tracking.xlsx` in OneDrive: **Tracking** sheet with `Status`, plus a **Completion** sheet (roster copy or surveyed IDs + `submitted`, `completed`, `reason_no_completion`) | yes (Status defaults to Open; the one shared file — agent, RA, and field team all edit it; no local copy) |
| `hfc/outputs/<MMDD>_HFCs.html` (titled `HFC MM/DD`, same on the detailed report; condensed: the daily message from `hfc/config/summary_condensed.md` plus the Completion, Duplicates and Form Version tables) | yes |
| `hfc/outputs/detailed/<MMDD>_HFCs_detailed.html` (also copied to the HFC Output Directory's `detailed/`) | yes (the full report: navigable, searchable tables) |
| Project `README.md` drafted from `assets/README_template.md` | yes (drafted automatically, no confirmation) |

## OneDrive (required)

| Item | Notes |
|---|---|
| `config.json` with Input Data Directory, HFC Output Directory, Code Output Directory all set to real paths (Media Folder Directory optional) | Skill-level config, no per-project override — HFC Output Directory is the OneDrive desktop app's synced local folder |
| Config pre-flight (A0) passes before any real work starts | No local-only mode — `require_hfc_config_ready()` stops the build otherwise |
| Folder shared with collaborators via OneDrive's own "Specific people" UI (once, by hand) | Code never mints its own share links |

## After post-feedback

| Item | Required |
|---|---|
| `hfc/code/resolutions/<Issue ID>.R` per resolved/reviewed finding, defining `fix(ds)` | yes |
| `<HFC Output Directory>/Updated Data/<stem>.<ext>` updated (raw unchanged) | yes |
| Today's `resolutions/<date>_issues_resolution.xlsx` clone has `Status` updated (`Resolved` / `Needs Review`) + `Corrections` — live `issue_tracking.xlsx` untouched until merge+commit | yes |
| `merge_resolutions.R` run, merged file reviewed with the user (AskUserQuestion), then `commit_merged_issue_tracking.R` run to update the live file | yes |

## Smoke

- [ ] On a true first-ever setup, `hfc/structure.html` opens *before* `hfc/outputs/<MMDD>_HFCs.html` at the final Review & Approve gate; on a rebuild, the report opens alone
- [ ] Detailed report tables searchable; GPS map present when M10 on and coordinates exist, with every valid-coordinate point shown; no flagged (red) points unless the project specifically turned on the advanced distance flag
- [ ] Detailed report: Last Day tab present and populated when a last date was confirmed
- [ ] Condensed report: header is just `HFC MM/DD` (no nav links), message first, then Completion (overall / by enumerator / by date, no issues table), Duplicates (only if any) and Form Version (summary + issues tables only when form version issues exist, else just "No form version issues found!"); the Completion section of BOTH reports states the formula (completed ÷ primary samples attempted); `Issues to highlight:` lists 2-5 items whenever the last day has issues; no "today"/numeric dates in either message (the builder prints warnings otherwise)
- [ ] M3: with no confirmed version windows, Expected Dates and mismatch findings come from each day's most-used form version
- [ ] Every table sorted by date (most recent first), then enumerator, then unique ID
- [ ] `issue_tracking.xlsx`, plus a copy of the condensed report and of the detailed report (in `detailed/`), present in the shared OneDrive-synced folder
- [ ] Grep: no hardcoded user home paths outside `hfc/code/main.R`
- [ ] If survey has pictures/audio: M13 on; filename cols not mis-filed under M14; M13 findings are dataset-level (one per fully-empty column), never per-row file-hygiene findings
- [ ] Nested skip-logic blanks not flagged as missing when form available
- [ ] If a completion signal was confirmed: M1 reports target-vs-actual (or primary/secondary composition) by group (Treatment/Control by default) and by enumerator; a "gating" signal's non-completed rows do not appear in any M2-M14 finding; a Reasons breakdown renders when gating found more than zero non-completions
- [ ] M8 straightlining fires at its defaults (100% per enumerator per day, min. 3 that day; 90% within one submission) unless explicitly overridden
- [ ] M7 Missingness shows only its reference tables (no findings) unless the project specifically turned on the advanced enumerator flag
- [ ] If M12 Balance Tables is on: gt-rendered tables appear right before All Issues, four per grouping, in order (Completed Interviews, By \<group\>, Completion Regression, Replacements); every M1 completion table reads Submitted | (Submitted (Primary Sample) when a primary sample is known) | Completed | Completion
- [ ] Country was inferred from data content (or an explicit column), not the input folder's name

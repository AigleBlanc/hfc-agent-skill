# README template — HFC Agent Skill survey project

Fill every section for **this survey's built product** — written to `<Code Output Directory>/README.md` (the configured, git-tracked output folder), not for the skill itself.
Use `assets/README_example.md` for the expected level of specificity. Confirm once with the user before finalizing.

## Contents

1. [Overview](#overview)
2. [Data](#data)
3. [Software requirements](#software-requirements)
4. [Instructions](#instructions)
5. [Outputs](#outputs)
6. [Folder structure](#folder-structure)
7. [AI / confidentiality](#ai--confidentiality)

---

## Overview

- Survey / project name:
- What this skill produces for this survey (HTML report, shared `issue_tracking.xlsx`, fixed data under an `Updated Data/` folder inside the HFC Output Directory):
- What it does **not** produce (e.g. cleaned analysis dataset, manuscript tables):
- Setup vs post-feedback: one sentence each

## Data

- Microdata path (the configured Input Data Directory — filename, format, approximate n rows / cols if known):
- Optional instrument / form path (also in the Input Data Directory):
- Access / confidentiality note (internal only, DUA, etc.):
- Rule: never mutate originals; agent-authored fixes write to `<HFC Output Directory>/Updated Data/<stem>.<ext>` instead — that folder name is set in `write_intermediate()`/`load_latest_dataset()` (`scripts/lib/utils.R`), the one place to change it if you'd rather it land elsewhere

## Software requirements

- R version tested:
- Install: `Rscript .claude/skills/hfc-agent-skill/install.R`
- Core packages: haven, readr, readxl, dplyr, tibble, lubridate, openxlsx, yaml, jsonlite, xml2
- OneDrive (required, no local fallback) — accessed as a plain local folder synced by the OneDrive desktop app, no extra package needed
- Recommended: geosphere (GPS distance, M10), gt/sandwich/lmtest (Balance Tables, M12)

## Instructions

### First-time setup

1. Configure `.claude/skills/hfc-agent-skill/config.json` — Input Data Directory (your microdata + optional form), Media Folder Directory (optional), HFC Output Directory, Code Output Directory.
2. Run `Rscript .claude/skills/hfc-agent-skill/install.R`.
3. In VS Code + Claude Code: **Run HFCs** or `/hfc-agent-skill`. The agent states its own best guess at each step; use **Other** to correct anything wrong — do not type `M1=Y M2=…`.
4. `issue_tracking.xlsx` lives in the OneDrive-synced folder named by `config.json`'s HFC Output Directory (required — no local fallback). Access is shared with collaborators once, by hand, via OneDrive's own sharing UI.

CLI equivalent after modules confirmed:

```bash
Rscript .claude/skills/hfc-agent-skill/scripts/run_setup_build.R --open
```

### After field feedback

1. Say **Process HFC feedback**. There's no built-in fix engine — the agent reads each Open row with a Comment and writes the fix itself, against a working clone (not the live file directly).
2. Review proposed fixes; confirm per row, then confirm the merged file before it's committed back to the live `issue_tracking.xlsx`.
3. Expect `<HFC Output Directory>/Updated Data/<stem>.<ext>` updated (raw file unchanged); `Status` set to `Resolved`/`Needs Review` in the live file only after that final confirm.

```bash
Rscript .claude/skills/hfc-agent-skill/scripts/apply_feedback.R clone
Rscript .claude/skills/hfc-agent-skill/scripts/apply_feedback.R list-open
Rscript .claude/skills/hfc-agent-skill/scripts/apply_feedback.R apply --finding-id "<Issue ID>" --corrections "<text>"
Rscript .claude/skills/hfc-agent-skill/scripts/merge_resolutions.R
Rscript .claude/skills/hfc-agent-skill/scripts/commit_merged_issue_tracking.R merged_issue_resolutions.xlsx
```

## Outputs

| Artifact | Path | Purpose |
|---|---|---|
| Product map | `hfc/structure.html` | Review tree in browser before Continue |
| HTML report | `hfc/outputs/<MMDD>_HFCs.html` | Navigable findings (searchable tables, GPS map) |
| Issue tracking | OneDrive-synced `issue_tracking.xlsx` (required, no local copy) | The one shared file — agent, RA, and field team all edit it |
| Findings | `hfc/outputs/issues.csv` | Machine-readable findings |
| Fixed data | `<HFC Output Directory>/Updated Data/<stem>.<ext>` | After Pipeline B; raw unchanged |

## Folder structure

List the configured directories (Input Data Directory, Media Folder Directory, HFC Output Directory, Code Output Directory) plus the `<Code Output Directory>/hfc/` tree after setup (`config/`, `instruments/`, `outputs/`, `code/` — `code/checks/`, `code/resolutions/`).

## AI / confidentiality

Point to `.claude/skills/hfc-agent-skill/references/ai_use.md`. Do not paste PII or restricted microdata into commercial AI tools.

# Gold-standard project README example (HFC Agent Skill)

Worked example of a **survey project** README the agent should aim for after setup, written to `<code_output_dir>/README.md` — calibrates the level of specificity expected (real paths/numbers, not placeholders). Pair with `README_template.md`.

---

## Overview

> This package runs High-Frequency Checks (HFCs) for an example household survey wave (illustrative name: Example Household Panel), reading microdata from the configured Input Data Directory. Setup builds an HTML report and a shared `issue_tracking.xlsx` synced to a OneDrive folder. Post-feedback writes agent-authored fixes to an `Updated Data/` folder inside the HFC Output Directory for Open+Field-Team-commented rows. It does **not** produce analysis tables for a paper or a cleaned longitudinal panel.

## Data

> **Survey microdata**
> - File: `household_panel_wave2.dta` (or `.csv` equivalent), in the configured Input Data Directory
> - Source: SurveyCTO export for this wave
> - Note: Original file is immutable. Applying a fix writes `<HFC Output Directory>/Updated Data/household_panel_wave2.dta` (or `.csv`) — one evolving fixed copy, updated as fixes accumulate. That folder name is set in `write_intermediate()`/`load_latest_dataset()` (`scripts/lib/utils.R`) if you'd rather it land elsewhere.
> - Form (optional): also in the Input Data Directory — improves M9 Field Request proposals (and M3 Form Version / M4 Duration section detection); setup proceeds without it.


## Software requirements

> - R ≥ 4.3 (tested with R 4.4 on macOS)
> - `Rscript .claude/skills/hfc-agent-skill/install.R` installs: haven, readr, readxl, dplyr, tibble, lubridate, openxlsx, yaml, jsonlite, xml2; geosphere/gt/sandwich/lmtest are recommended (GPS distance, Balance Tables)
> - OneDrive is required — a plain local folder synced by the OneDrive desktop app, no extra R package needed


## Instructions

> 1. Confirm `.claude/skills/hfc-agent-skill/config.json` is fully configured (Input Data Directory, HFC Output Directory, Code Output Directory; Media Folder Directory optional).
> 2. Run `Rscript .claude/skills/hfc-agent-skill/install.R`.
> 3. In Claude Code (VS Code): **Run HFCs** or `/hfc-agent-skill`. The agent first confirms `config.json` is reachable (required — stops with setup instructions if not), then walks through config reuse (if a prior run exists) and a Setup window (files found + any specific instructions). Everything else — Entity Label, country, duplicate key, timing/GPS/media/consent columns, and every module setting — is determined by the agent itself, from the data, and applied silently; review the finished report and either approve it or say "Walk me through all modules" to replay every one of those decisions for correction. Use **Other** to correct anything wrong. Do not type `M1=Y M2=…`.
> 4. Open `hfc/outputs/<MMDD>_HFCs.html` (builder may auto-open). Field/RA edit `issue_tracking.xlsx` directly in the shared OneDrive-synced folder (access set up once, by hand).
> 5. Later: **Process HFC feedback** once Comments exist on Open rows in `issue_tracking.xlsx` — the agent reads each row and writes the fix itself, against a working clone, then merges back after confirmation (choose options to proceed).
>
> CLI after `hfc/config/modules.yaml` exists:
> ```bash
> Rscript .claude/skills/hfc-agent-skill/scripts/run_setup_build.R --open
> Rscript .claude/skills/hfc-agent-skill/scripts/apply_feedback.R clone
> Rscript .claude/skills/hfc-agent-skill/scripts/apply_feedback.R list-open
> ```


## Outputs

> - `hfc/structure.html` — product tree (review before Continue)
> - `hfc/outputs/<MMDD>_HFCs.html` — the short daily update (completion, reasons, enumerators, issues to highlight), plus Completion, Duplicates and Form Version tables
> - `hfc/outputs/detailed/<MMDD>_HFCs_detailed.html` — findings by module (searchable tables, GPS map); also copied to the shared output folder's `detailed/`
> - OneDrive-synced `issue_tracking.xlsx` (required, no local copy) — the one shared file; agent, RA, and field team all edit it
> - `.claude/skills/hfc-agent-skill/config.json` — Input Data Directory / Media Folder Directory / HFC Output Directory / Code Output Directory / Main Tracking Filename; skill-level, not per-project
> - `hfc/outputs/issues.csv` — stable, content-derived Issue IDs

## Folder structure

> - Input Data Directory (configured, external) — immutable microdata
> - `<HFC Output Directory>/Updated Data/` — agent-fixed data (one evolving file per source, raw untouched)
> - `<Code Output Directory>/hfc/code/checks/` — real, runnable per-module scripts + custom (e.g. `example_check.R`)
> - `<Code Output Directory>/hfc/code/resolutions/` — agent-authored fix code, one `<Issue ID>.R` per resolved finding
> - `<Code Output Directory>/hfc/code/main.R` — skill/code-output-path entry
> - `<Code Output Directory>/hfc/outputs/`, `hfc/instruments/`, `hfc/config/`
> - `.claude/skills/hfc-agent-skill/` — drop-in skill (do not edit unless upgrading the skill)

## AI / confidentiality

> Household / school microdata must not be pasted into commercial AI tools. See `.claude/skills/hfc-agent-skill/references/ai_use.md`.

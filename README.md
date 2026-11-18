# HFC Agent Skill

This skill runs High-Frequency Checks on your survey data, builds a short HTML update and a detailed HTML report, and gives you one shared spreadsheet (`issue_tracking.xlsx`) where the field team, the RA, and the AI agent all track and resolve data-quality issues together.

It's a skill for **Claude Code** (desktop app or the VS Code extension) — not a generic chatbot, and not usable stand-alone. It also needs **R** installed locally, and the **OneDrive desktop app** (required) to keep the shared tracking file in sync. It never touches your original data file: every fix is written to a separate copy (an `Updated Data` folder inside your **HFC Output Directory**), so your raw export always stays exactly as it was collected.

---

## 0. Prerequisites (one-time, before you begin)

If any of these are new to you, install them first — everything below assumes they're already on your computer:

| Need | What it is | Get it |
|---|---|---|
| **Claude Code** | The AI coding assistant this skill runs inside. Either the desktop app or the VS Code extension | [claude.com/claude-code](https://claude.com/claude-code) |
| **VS Code** | The code editor Claude Code runs inside (skip this if you're using the Claude Code desktop app instead) | [code.visualstudio.com](https://code.visualstudio.com) |
| **R** | The statistics language this skill's checks are written in. Don't worry, you won't write any R yourself, the agent runs it for you | [cran.r-project.org](https://cran.r-project.org) (macOS/Windows/Linux installers) |
| **git** (optional) | Used once, to download this skill onto your computer. Also recommended for your **Code Output Directory**, though the skill itself never runs git | [git-scm.com](https://git-scm.com) |
| **OneDrive desktop app** (required) | Keeps the shared `issue_tracking.xlsx` spreadsheet in sync between you, your RA, and the field team | Usually pre-installed on work computers; otherwise [onedrive.com](https://www.microsoft.com/en-us/microsoft-365/onedrive/download) — install and sign in with your organization account before Step 2 below. The skill has no local-only fallback |

**A terminal is where you'll type the two commands in Step 2.** On macOS, open the "Terminal" app; on Windows, open "Command Prompt" or "PowerShell"; in VS Code, use its built-in terminal (menu: Terminal → New Terminal). "From the parent directory of `.claude/`" below means: navigate there first — e.g. type `cd path/to/your/survey/project` — before running the command.

## 1. Install it

From the project folder you'll actually work in (the folder open on your VS Code or git app), clone this repo straight into `.claude/skills/hfc-agent-skill/` — safe to do even if `.claude/` already exists with other skills or settings in it, since this only creates that one new subfolder:

```bash
mkdir -p .claude/skills
git clone git@github.com:AigleBlanc/hfc-agent-skill.git .claude/skills/hfc-agent-skill
```

**Open your project folder** (the one containing `.claude/`) in VS Code with Claude Code. Turn on Claude Code's built-in **Auto** permission mode (`/permissions`, or the mode toggle) so the agent doesn't interrupt you for routine file reads/writes and `Rscript` calls — it's a setting you control yourself, not something this skill changes for you.

## 2. Two things YOU need to run yourself

Everything else in this skill is run automatically by the AI agent when you talk to it, that is you never type an `Rscript` command by hand for normal use. Only these two setup steps are on you, and **both are required**.

**a) Install the R packages** (once, from a terminal at the parent directory of `.claude/`):
```bash
Rscript .claude/skills/hfc-agent-skill/install.R
```

**b) Configure `config.json`** (once, at `.claude/skills/hfc-agent-skill/config.json`) — four directories plus one optional filename. The file ships with placeholders you need to replace:
```json
{
    "Input Data Directory": "/path/to/your/survey/data",
    "Media Folder Directory": "",
    "HFC Output Directory": "/Users/you/OneDrive - Your Org/HFC Reports",
    "Code Output Directory": "/path/to/a/git/repo/you/manage",
    "Main Tracking Filename": "issue_tracking.xlsx"
}
```
For example, on a Mac, a filled-in version might look like this — an absolute path always starts from the very top of your file system (`/Users/...` on Mac, `C:\Users\...` on Windows), not a shortcut like `~` or a relative folder name:
```json
{
    "Input Data Directory": "/Users/jane/Documents/uganda_survey/data",
    "Media Folder Directory": "/Users/jane/Documents/uganda_survey/data/media",
    "HFC Output Directory": "/Users/jane/OneDrive - MyOrg/HFC Reports/uganda_survey",
    "Code Output Directory": "/Users/jane/code/uganda_survey_hfc",
    "Main Tracking Filename": "issue_tracking.xlsx"
}
```

| Directory | What it's for |
|---|---|
| **Input Data Directory** | Your survey microdata export, and everything described in the next section — never modified |
| **Media Folder Directory** | Optional; your SurveyCTO audio/photo attachments folder |
| **HFC Output Directory** | A folder the OneDrive desktop app is syncing, for the shared `issue_tracking.xlsx` (install and sign in to OneDrive first; this skill just reads/writes the local synced folder like any other). Share it with your RA/field team via OneDrive's normal "Share" button so they can open and edit `issue_tracking.xlsx` directly |
| **Code Output Directory** | A folder you manage yourself (ideally a git repo); the built `hfc/` report, config and checks land here. This skill only ever writes plain files there — it never runs git for you |
| **Main Tracking Filename** | Optional; name of the shared tracking file if you don't want the default `issue_tracking.xlsx` |

If `config.json` still has placeholders, the agent will tell you and stop before doing any real work. Do this first!

## 3. Before you start: what goes in your Input Data Directory

The agent looks for everything it needs inside your **Input Data Directory** — and nowhere else (subfolders are fine; it searches those too). So before your first run, drop everything below into that one folder:

| File | What it's for |
|---|---|
| Your survey microdata export | Required, the de-identified data itself. BEWARE that if you share PII, the AI agent will read that too |
| Survey instrument (SurveyCTO/ODK XLSForm `.xlsx`) | Optional, but lets the agent understand your form's questions, skip logic, and choice lists |
| Pre-analysis plan / project description | Optional background reading only (PDF, Word, text, or Markdown) — never treated as a data source, never overrides what the actual data shows |
| Sample roster (primary + replacement list) | **Strongly recommended for RCTs.** It drives primary-vs-replacement tracking and how completion is measured (against the primary sample). Optional otherwise; the agent will ask if it can't find one |

Everything must sit under this one parent directory — that's the only place the agent looks. You don't need to name or label the files: the agent opens the candidates and decides for itself which is the microdata, the form, the roster and the project document, rather than going by filename. Project documents can be PDF, `.docx`, text or Markdown; an old binary `.doc` can't be read, so export it to `.docx` or PDF first.

## 4. Run it

In Claude Code, just talk to it in plain language. Two things to say:

| Say this | When |
|---|---|
| **"Run HFCs"** | First time, or whenever you want to re-check the data (e.g. new submissions came in) |
| **"Process HFC feedback"** | After the field team/RA has written comments on flagged rows in `issue_tracking.xlsx` |

Close variants also work ("Start HFCs", "Run HFC fixes", "Apply field feedback"), as does the `/hfc-agent-skill` command, or anything that tells Claude Code you want high-frequency checks run on a dataset (e.g. "Run HFCs for project x").

The agent only stops to ask you a handful of things (at most five during "Run HFCs"), using clickable option cards. It states its own best guess first; you pick "Looks good" or choose "Other" and type a correction. You never type long answers.

---

## How "Run HFCs" works

1. **Config check.** The agent confirms `config.json` is fully filled in. If not, it stops and tells you what to fix.
2. **Reuse prompt (only on a re-run).** If a saved setup from a previous run exists (`hfc/config/role_map.yaml` and `modules.yaml`), you choose: reuse it and rebuild, start fresh, or edit the config files by hand first.
3. **Data found.** It finds your files (making an extra effort to find your sample roster, opening every sheet of every candidate), then shows the paths it picked plus the row count, column count and collection dates. If it can't find a roster it says so and asks whether one exists.
4. **Instructions.** You can tell it anything it should know up front: checks to switch off, the country, specific checks you want (e.g. "flag interviews under 10 minutes"). It also writes a blank `hfc/config/modules.yaml` you can pre-fill yourself. Requests that match a standard check adjust that check; anything else becomes a custom Field Request (M9) check.
5. **Completion signal (only when one is found).** The agent shows how it will tell which planned surveys were completed (a screening/eligibility question, a target roster, or a primary/secondary column) and the reason labels it will use. If your roster has no column that separates primary from replacement respondents, or some submitted IDs are not on the roster, the agent asks you what to do rather than assuming. Once confirmed, the other checks run only on completed surveys.
6. **Everything else is decided for you.** Respondent ID, enumerator, country and timezone, timing and GPS columns, important variables, thresholds and labels are chosen by the agent and saved to `hfc/config/role_map.yaml` and `modules.yaml`, with no questions. You can review any of it at the end.
7. **Build.** It runs the checks (M1–M14), writes two HTML reports and drafts your project README. The short one summarizes the **last day** of data collection (named by its date, e.g. "Aug 17", never "today") and is also posted in chat, ready to share; the detailed one lists every finding. Both are titled `HFC MM/DD` (the day they were generated).
8. **Review & Approve.** Your browser opens `hfc/structure.html` (first setup only) and then the short report `hfc/outputs/<MMDD>_HFCs.html` (the detailed report stays in `detailed/`). You then choose one of three paths:
   - **All good!** The findings are committed to the live shared `issue_tracking.xlsx`.
   - **Walk me through all modules.** The agent replays each setting as a quick confirm-or-correct pass, then rebuilds.
   - **Other.** Describe a fix, or say you've hand-edited `modules.yaml` or `role_map.yaml`; the agent re-reads them, rebuilds and asks again.

Until you approve, the live `issue_tracking.xlsx` is never touched; the new findings wait in a pending file. On a re-run, nothing the field team already wrote is lost or silently dropped.

## How "Process HFC feedback" works

The field team and RA write comments directly into `issue_tracking.xlsx` (Comment column) on any row they want fixed. Once that's done:

1. Say **"Process HFC feedback"**.
2. The agent copies the tracking file to a working clone (`resolutions/<YYYYMMDD>_issues_resolution.xlsx`) and finds every row that's `Open` and has a comment. It asks you once to proceed with all of them or only some.
3. For each row, the agent writes the fix in code (saved under `hfc/code/resolutions/`), applies it to a copy of the data, and sets the `Status` and `Corrections`, all in the clone. Anything it can't confidently fix is marked `Needs Review`.
4. It merges the clone back into a pending file and shows you the counts (Resolved / Needs Review).
5. Only after you confirm does the live `issue_tracking.xlsx` get updated.
6. It then rebuilds the report against the fixed data. Resolved findings disappear from the detailed report, but the spreadsheet keeps the full history.

### What the `Status` column means

| Status | What it means | Who sets it |
|---|---|---|
| `Open` | Not yet resolved — the default | Automatic |
| `Accepted` | Field/RA confirms this is a real issue (optional — not required for the agent to act) | Field team / RA |
| `Revise` | Field/RA disagrees with the flag | Field team / RA |
| `Resolved` | The agent applied a fix | Agent, after you confirm |
| `Needs Review` | The agent couldn't confidently fix it — needs a human look | Agent, after you confirm |

You don't have to set `Accepted` before the agent will act — it picks up any `Open` row that has a comment.

---

## Where things end up

| What | Where |
|---|---|
| Condensed report (short update, titled `HFC MM/DD`) | `<Code Output Directory>/hfc/outputs/<MMDD>_HFCs.html`, with a copy in your HFC Output Directory. One page: the daily message (that day's submissions and completions, cumulative completion against the primary sample (completed surveys, primary samples attempted, and the completion rate), non-completion reasons, the enumerator roster and 2 to 5 issues to highlight) followed by the Completion (overall, by enumerator, by date), Duplicates (if any) and Form Version tables (the Completion section explains how Completion is computed; Form Version shows its summary and issues tables only when there are form version issues, otherwise just "No form version issues found!") |
| Detailed report (full findings) | `<MMDD>_HFCs_detailed.html` in a `detailed/` subfolder of both `hfc/outputs/` and your HFC Output Directory |
| Product map (first setup) | `<Code Output Directory>/hfc/structure.html` |
| Saved settings you can hand-edit | `<Code Output Directory>/hfc/config/role_map.yaml` and `modules.yaml` |
| Runnable check scripts | `<Code Output Directory>/hfc/code/checks/` (`main.R` runs them all) |
| Your project README | `<Code Output Directory>/README.md` |
| Shared tracking file | `issue_tracking.xlsx` — in your configured **HFC Output Directory** (required, no local copy). Two sheets: **Tracking** (flagged issues) and **Completion** (one row per respondent in your sample, with `submitted`, `completed` and `reason_no_completion`) |
| Dated snapshots | `<HFC Output Directory>/intermediate/` (one per setup run) and `resolutions/` (working clone for feedback passes) |
| Fixed data (raw is never touched) | `<HFC Output Directory>/Updated Data/<stem>.<ext>` |
| Your original data | your **Input Data Directory** — never modified |

Fixed data always lands at `<HFC Output Directory>/Updated Data/<stem>.<ext>` (one evolving file per source, updated as fixes accumulate) — that folder name is set in `write_intermediate()`/`load_latest_dataset()` in `scripts/lib/utils.R`, so if you'd rather it land somewhere else, that's the one place to change it.

## What the checks are

Fourteen modules, M1–M14: Completion, Duplicates, Form Version, Survey Duration, Irregular Timing, Numeric Outliers, Missingness, Straightlining, Field Request, GPS Map, Summary Statistics, Balance Tables, Media files, and Consent/assent/audio flags. A few defaults are worth knowing:

- **Completion** means whether all *planned* surveys were conducted, not whether a started survey was finished. Every completion table reads Submitted, Submitted (Primary Sample), Completed, Completion; where a roster (or a primary/secondary column) marks the primary sample, Completion = Completed (primary or replacement) ÷ Submitted (Primary Sample), so it can pass 100% when replacements completed for primaries that never submitted. Without a primary sample the second column is dropped and Completion = Completed ÷ Submitted. Anything the roster doesn't say (no primary/replacement column, IDs missing from it) is asked, never assumed. Each respondent's result also lands in the **Completion** sheet of `issue_tracking.xlsx`.
- **Form Version** compares each submission's form version with the version expected for its date. The expected version comes from the date windows in `modules.yaml`; where none are set, it is each day's most-used version (and a version's expected dates are the first to last day it led).
- **Missing-value codes** `-99, -999, -9999, 999, 9999, 99999` are treated as missing in every numeric check and statistic, so they are never flagged as outliers. Tell the agent (or add to `M7.sentinel_codes` in `modules.yaml`) any extra codes your survey uses; they are added to these.
- **GPS Map** and **Missingness** are descriptive only by default: they show data but don't flag anything.
- **Field Request** is empty unless you ask for a custom check in the Instructions step.

Details for each are in [`references/check_modules.md`](references/check_modules.md).

## What's included

| File / folder | Purpose |
|---|---|
| `SKILL.md` | The agent's own step-by-step instructions for running HFCs |
| `config.json` | Your four configured directories (plus optional tracking filename) |
| `install.R` | One-time R package installer |
| `references/ai_use.md` | Where PII can and can't go (commercial AI tools) |
| `references/check_modules.md` | What each check (M1–M14) does and its default settings |
| `references/checklist.md` | Setup checklist the agent works through |
| `references/flags.md` | Known-mistake list the agent checks itself against |
| `references/interaction.md` | Wording for the confirmation prompts the agent shows you |
| `references/issue_tracking_schema.md` | Column-by-column reference for `issue_tracking.xlsx` |
| `references/prompts.md` | The exact phrases that start setup vs. post-feedback |
| `references/role_map_schema.md` | The field-by-field `role_map.yaml` schema the agent writes during setup |
| `assets/report_sections.json` | The table layout every section of the detailed report follows (and which trimmed sections the condensed report keeps) |
| `assets/summary_message_example.md` | Worked example the agent drafts the detailed report's long summary against |
| `assets/summary_condensed_example.md` | Worked example the agent drafts the short update (and the chat message) against |
| `assets/main.R` | Internal — template for `hfc/code/main.R`, a cheat-sheet of every step you could run by hand |
| `assets/README_template.md`, `assets/README_example.md` | Template the agent fills in to write your own project's README |
| `assets/check_templates/` | Internal — one script per check; copied into `hfc/code/checks/` on each build (the copies are the ones you can run) |
| `scripts/`, `scripts/lib/` | Internal — the R engine behind every check; you never run these by hand |
| `tests/` | Internal dev test suite; gitignored, not part of the shipped skill |

## Developer's advice

An AI skill is not a fixed instruction file, what you tell the agent in your Claude Code chat will modify what this skill does. So if you have suggestions related to your specific
project/needs, like additional checks or how to report some issues, tell the AI agent and it will adjust to your instructions. This skill is a starting point, tell the AI agent what to change! You can also hand-edit `hfc/config/modules.yaml` or `role_map.yaml` yourself and tell the agent to re-read them.

It is also advised to turn your Claude Code interaction mode to "Auto" so that the agent does not request your permissions to run R scripts and file reading/writing a thousand times.


## A note on privacy 

Don't paste respondent-level data into commercial AI chat tools. See [`references/ai_use.md`](references/ai_use.md) for details.

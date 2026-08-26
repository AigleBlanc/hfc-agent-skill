# HFC Agent Skill

This skill runs High-Frequency Checks on your survey data, builds an HTML report, and gives you one shared spreadsheet (`issue_tracking.xlsx`) where the field team, the RA, and the AI agent all track and resolve data-quality issues together.

It's a skill for **Claude Code** (desktop app or the VS Code extension) — not a generic chatbot, and not usable stand-alone. It also needs **R** installed locally, and the **OneDrive desktop app** for the shared tracking file if you choose to store you data or output in OneDrive. It never touches your original data file: every fix is written to a separate copy (an `Updated Data` folder inside your **HFC Output Directory**), so your raw export always stays exactly as it was collected.

---

## 0. Prerequisites (one-time, before you begin)

If any of these are new to you, install them first — everything below assumes they're already on your computer:

| Need | What it is | Get it |
|---|---|---|
| **Claude Code** | The AI coding assistant this skill runs inside. Either the desktop app or the VS Code extension | [claude.com/claude-code](https://claude.com/claude-code) |
| **VS Code** | The code editor Claude Code runs inside (skip this if you're using the Claude Code desktop app instead) | [code.visualstudio.com](https://code.visualstudio.com) |
| **R** | The statistics language this skill's checks are written in. Don't worry, you won't write any R yourself, the agent runs it for you | [cran.r-project.org](https://cran.r-project.org) (macOS/Windows/Linux installers) |
| **git** (optional) | Used once, to download this skill onto your computer | [git-scm.com](https://git-scm.com) |
| **OneDrive desktop app** (optional) | Keeps the shared `issue_tracking.xlsx` spreadsheet in sync between you, your RA, and the field team | Usually pre-installed on work computers; otherwise [onedrive.com](https://www.microsoft.com/en-us/microsoft-365/onedrive/download) — install and sign in with your organization account before Step 2 below |

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

**b) Configure `config.json`** (once, at `.claude/skills/hfc-agent-skill/config.json`) — four directories. The file ships with placeholders you need to replace:
```json
{
    "Input Data Directory": "/path/to/your/survey/data",
    "Media Folder Directory": "",
    "HFC Output Directory": "/Users/you/OneDrive - Your Org/HFC Reports",
    "Code Output Directory": "/path/to/a/git/repo/you/manage"
}
```
For example, on a Mac, a filled-in version might look like this — an absolute path always starts from the very top of your file system (`/Users/...` on Mac, `C:\Users\...` on Windows), not a shortcut like `~` or a relative folder name:
```json
{
    "Input Data Directory": "/Users/jane/Documents/uganda_survey/data",
    "Media Folder Directory": "/Users/jane/Documents/uganda_survey/data/media",
    "HFC Output Directory": "/Users/jane/OneDrive - MyOrg/HFC Reports/uganda_survey",
    "Code Output Directory": "/Users/jane/code/uganda_survey_hfc"
}
```

| Directory | What it's for |
|---|---|
| **Input Data Directory** | Your survey microdata export, and everything described in the next section — never modified |
| **Media Folder Directory** | Optional; your SurveyCTO audio/photo attachments folder |
| **HFC Output Directory** | A folder the OneDrive desktop app is syncing, for the shared `issue_tracking.xlsx` (install and sign in to OneDrive first; this skill just reads/writes the local synced folder like any other). Share it with your RA/field team via OneDrive's normal "Share" button so they can open and edit `issue_tracking.xlsx` directly |
| **Code Output Directory** | A folder you manage yourself (ideally a git repo); the built `hfc/` report and checks land here. This skill only ever writes plain files there — it never runs git for you |

If `config.json` isn't fully configured yet, the agent will tell you and stop before doing any real work. Do this first!

## 3. Before you start: what goes in your Input Data Directory

The agent looks for everything it needs inside your **Input Data Directory** — and nowhere else (subfolders are fine; it searches those too). So before your first run, drop everything below into that one folder:

| File | What it's for |
|---|---|
| Your survey microdata export | Required, the de-identified data itself. BEWARE that if you share PII, the AI agent will read that too |
| Survey instrument (SurveyCTO/ODK XLSForm `.xlsx`) | Optional, but lets the agent understand your form's questions, skip logic, and choice lists |
| Pre-analysis plan / project description | Optional background reading only (PDF, Word, text, or Markdown) — never treated as a data source, never overrides what the actual data shows |
| Target/planned-sample roster | Optional; only needed if you're tracking primary vs. replacement respondents against a planned sample |

Everything must sit under this one parent directory — that's the only place the agent looks.

## 4. Run it

In Claude Code, just talk to it in plain language. Two things to say:

| Say this | When |
|---|---|
| **"Run HFCs"** | First time, or whenever you want to re-check the data (e.g. new submissions came in) |
| **"Process HFC feedback"** | After the field team/RA has written comments on flagged rows in `issue_tracking.xlsx` |

The agent will ask you questions along the way using clickable option cards (never type long answers — just pick an option, or choose "Other" if nothing fits and type your suggestions there).  

NOTE: You can also say something like "Run HFCs for project x" or anything that indicates the Claude Code that you want to use the skill to high-frequency checks on a dataset. 

---

## How "Run HFCs" works

1. The agent finds your data (and form, if you have one) and shows you its own best guess for a handful of things: what column identifies each respondent, what to call it in the report, and the data-collection country, all in one screen. Type a correction if anything's wrong; otherwise just confirm it looks right.
2. It proposes how it'll run each check (M1–M14: duplicates, outliers, GPS, timing, missing data, etc.); again as its own best guess, grouped into a couple of screens, never a long list of options to choose from.
3. It builds the report and opens `hfc/outputs/<MMDD>_HFCs.html` in your browser.
4. It creates (or updates) `issue_tracking.xlsx` — one row per flagged issue.

If `issue_tracking.xlsx` already exists (a second run), the agent doesn't overwrite it blindly — it shows you exactly what changed and asks you to confirm before anything is replaced. Nothing the field team already wrote is ever lost or silently dropped.

## How "Process HFC feedback" works

The field team and RA write comments directly into `issue_tracking.xlsx` (Comment column) on any row they want fixed. Once that's done:

1. Say **"Process HFC feedback"**.
2. The agent finds every row that's still `Open` and has a comment, and shows you the list.
3. For each one, the agent writes the fix in code, applies it to a copy of the data, and proposes what the `Status` and `Corrections` should say.
4. Once all rows are handled, it shows you a summary of what will change in the shared tracking file and asks you to confirm.
5. Only after you confirm does the live `issue_tracking.xlsx` actually get updated.

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
| HTML report | `<Code Output Directory>/hfc/outputs/<MMDD>_HFCs.html` |
| Shared tracking file | `issue_tracking.xlsx` — in your configured **HFC Output Directory** (required, no local copy) |
| Fixed data (raw is never touched) | `<HFC Output Directory>/Updated Data/<stem>.<ext>` |
| Your original data | your **Input Data Directory** — never modified |

Fixed data always lands at `<HFC Output Directory>/Updated Data/<stem>.<ext>` (one evolving file per source, updated as fixes accumulate) — that folder name is set in `write_intermediate()`/`load_latest_dataset()` in `scripts/lib/utils.R`, so if you'd rather it land somewhere else, that's the one place to change it.

## What's included

| File / folder | Purpose |
|---|---|
| `SKILL.md` | The agent's own step-by-step instructions for running HFCs |
| `config.json` | Your four configured directories |
| `install.R` | One-time R package installer |
| `references/ai_use.md` | Where PII can and can't go (commercial AI tools) |
| `references/check_modules.md` | What each check (M1–M14) does and its default settings |
| `references/checklist.md` | Setup checklist the agent works through |
| `references/flags.md` | Known-mistake list the agent checks itself against |
| `references/interaction.md` | Wording for the confirmation prompts the agent shows you |
| `references/issue_tracking_schema.md` | Column-by-column reference for `issue_tracking.xlsx` |
| `references/prompts.md` | The exact phrases that start setup vs. post-feedback |
| `references/role_map_schema.md` | The field-by-field `role_map.yaml` schema the agent writes during setup |
| `assets/report_sections.json` | The table layout every report section follows |
| `assets/summary_message_example.md` | Worked example the agent drafts your daily summary against |
| `assets/README_template.md`, `assets/README_example.md` | Template the agent fills in to write your own project's README |
| `assets/check_templates/` | Internal — one script per check; not run directly |
| `scripts/`, `scripts/lib/` | Internal — the R engine behind every check; you never run these by hand |
| `tests/` | Internal dev test suite; gitignored, not part of the shipped skill |

## Developer's advice

An AI skill is not a fixed instruction file, what you tell the agent in your Claude Code chat will modify what this skill does. So if you have suggestions related to your specific
project/needs, like additional checks or how to report some issues, tell the AI agent and it will adjust to your instructions. This skill is a starting point, tell the AI agent what to change! 

It is also adviced to turn your Claude Code interaction mode to "Auto" so that the agent does not request your permissions to run R scripts and file reading/writing a thousand times.


## A note on privacy 

Don't paste respondent-level data into commercial AI chat tools. See [`references/ai_use.md`](references/ai_use.md) for details.

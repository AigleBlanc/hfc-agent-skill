# role_map.yaml schema

The canonical field list for `<Code Output Directory>/hfc/config/role_map.yaml`. Nothing in the pipeline detects or guesses these any more — every field in the first table below is determined by the agent itself, reading `scripts/profile_dataset.R`'s output (column names, types, labels, missingness, cardinality, sample values) like an analyst would, and written directly with the Write/Edit tool. `scripts/lib/validate_config.R` hard-stops the build, naming the exact missing field, if any of them isn't present at all — write it explicitly, even as `null`/an empty list, when it genuinely doesn't apply to this survey. See `SKILL.md`'s A1/A2 for when each field gets determined.

## Agent-determined

| Field | Type | Meaning |
|---|---|---|
| `data_file_path` | string, required | Absolute path to the chosen microdata file. |
| `form_file_path` | string or `null` | Absolute path to the survey instrument (XLSForm), if one exists. |
| `roster_file_path` | string or `null` | Absolute path to the planned sample roster (primary + replacement respondents), if one exists. Found by SKILL.md A1's roster hunt (every candidate, all sheets); `null` only after that hunt and a direct question to the user. |
| `context_doc_path` | string or `null` | Absolute path to a PAP/project-description document, if one exists — background reading only. |
| `entity_id` | string, required | Column identifying each respondent/case/household. |
| `entity_id_sep` | string | Separator for composite IDs. Fixed default `" / "` — only set to override. |
| `entity_name_field` | string or `null` | Column holding the entity's human-readable name, if the survey captures one. |
| `entity_label` | string | Title-Case noun for the entity (e.g. "Household") — used across the report and tracking sheet. |
| `group` | string or `null` | Site/cluster/facility column. |
| `group_name` | string or `null` | Human-readable name field for `group`, if separate from its ID. |
| `group_label` | string | Title-Case noun for `group` (e.g. "School"). |
| `enum` | string or `null` | Enumerator/interviewer ID column. |
| `enum_name` | string or `null` | Human-readable name field for `enum`, if separate from its ID. |
| `start` | string or `null` | Interview start-timestamp column. |
| `end` | string or `null` | Interview end-timestamp column. |
| `duration` | string or `null` | Interview duration column (minutes), if the form doesn't only give start/end. |
| `x` | string or `null` | GPS longitude column. |
| `y` | string or `null` | GPS latitude column. |
| `age` | string or `null` | Respondent age column. |
| `assent` | string or `null` | Child's own assent-flag column. |
| `consent` | string or `null` | Guardian/parental consent-flag column. |
| `audio_flag` | string or `null` | Audio-consent flag column (distinct from an audio filename column). |
| `audio_file_cols` | list of strings | Columns holding audio filenames. |
| `image_file_cols` | list of strings | Columns holding image filenames. |
| `consent_image` | string or `null` | Which `image_file_cols` entry is the signed-consent photo. |
| `assent_image` | string or `null` | Which `image_file_cols` entry is the child-assent photo. |
| `form_version_col` | string or `null` | Column recording which form version a submission used. |
| `dup_key_extra` | list of strings | Extra columns (round/wave/phase-like) that disambiguate `entity_id` for M2, when a respondent legitimately repeats across rounds. |
| `section_time_pairs` | map of label to `{start:, end:}` | Section-level timing pairs available for M4's optional per-section breakdown (only applied if you also set `modules.yaml`'s `M4.section_pairs`). |
| `ordinal_vars` | list of strings | Likert/ordinal-shaped columns (3–7 ordered values) worth checking for straightlining — feeds M8 directly. |
| `country_mode` | `"single"` or `"multi"` | Fixed default `"single"` — only set to `"multi"` on explicit instruction. |
| `country` | string | The data-collection country (or countries, multi-mode). |
| `country_col` | string or `null` | Column holding the country value — multi-country mode only. |
| `country_timezone_map` | map of country value to IANA tz | Multi-country mode only — must cover every country value present in the data. |
| `timezone` | string | IANA timezone (e.g. `"Africa/Kampala"`) — single-country mode. Required; there is no fallback to the machine's local timezone. |
| `entity_display` | `"id"` or `"name"` | De-identification default `"id"` — override only on request. |
| `enumerator_display` | `"id"` or `"name"` | De-identification default `"name"`. |
| `group_display` | `"id"` or `"name"` | De-identification default `"name"`. |
| `important_vars` | list of strings, ≤10 | The unified shortlist driving M6/M11 — mandatory every run. |
| `missingness_extra_vars` | list of strings | Extra variables (beyond `important_vars`) reported in M7's missingness table. |
| `var_labels` | map of column to label | Human-readable label for every column that can surface in a finding. |
| `treatment_control_col` / `treatment_control_label` | string or `null` | Treatment/Control column and label, if the survey has one. |
| `geo_group_col` / `geo_group_opted_in` | string or `null` / boolean | Geography grouping column and whether to add it alongside Treatment/Control. |
| `qualitative_text_cols` | list of strings | Open-text columns capturing qualitative data, for M13's "other" column set. |
| `map_focus` | `"world"`, `"country"`, or `"city"` | Initial GPS map zoom level. |
| `last_date` | string (`YYYY-MM-DD`) | Confirmed last date of data collection to report against. |

## Derived automatically — do not write these yourself

`profile_roles()` recomputes these fresh from the data on every build, on top of whatever you've already written above; anything you write here is overwritten.

| Field | Meaning |
|---|---|
| `key` | The machine-generated unique submission key (SurveyCTO/ODK `key`/`uuid`/`instanceID`). |
| `completion_var_candidates`, `completion_signal_types`, `completion_status_col`, `completion_status_complete_values`, `completion_primary_secondary_col`, `completion_primary_value`, `completion_roster_candidate` | M1's completion-signal detection. Unconditionally recomputed every build — even though SKILL.md's A1 step 11 has the agent write `completion_roster_candidate`/`completion_primary_secondary_col`/`completion_primary_value` to `role_map.yaml` too (for the current run's use), that write is discarded and replaced fresh on the very next build regardless. |
| `completion_primary_signal` | The one exception in this group: `profile_roles()` only fills this in when it's blank, so the value SKILL.md's A1 has the agent confirm and write (via the Completion Signal gate) IS preserved across rebuilds, unlike its neighbors above. |
| `has_gps`, `has_consentish`, `has_media` | Booleans derived from the fields above; drive M10/M14/M13's on/off defaults respectively. |
| `has_enum`, `has_group` | Booleans derived from the fields above (whether `enum`/`group` is set). Informational only — neither currently drives any module's on/off default. |
| `last_date_candidate` | The max date seen in the data, distinct from the confirmed `last_date`. |
| `flag_weekend_default` | Data-driven default for whether M5 flags weekend submissions. |
| `media_folder`, `media_folder_found` | Mirrors `config.json`'s Media Folder Directory. |

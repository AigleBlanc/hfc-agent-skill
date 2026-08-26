# Setup build — runs every check and produces the report + tracking files.
# Rscript run_setup_build.R [--open] [--sample N]
# config.json must already be configured. Raw microdata is read in place
# and never copied.

.resolve_skill <- function() {
    sp <- {
    ca <- commandArgs(trailingOnly = FALSE)
    fa <- grep("^--file=", ca, value = TRUE)
    if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
    }
    if (!is.na(sp) && file.exists(sp)) {
    return(normalizePath(file.path(dirname(sp), "..")))
    }
    if (file.exists(".claude/skills/hfc-agent-skill/scripts/lib/utils.R")) {
    return(normalizePath(".claude/skills/hfc-agent-skill"))
    }
    if (file.exists("hfc-agent-skill/scripts/lib/utils.R")) {
    return(normalizePath("hfc-agent-skill"))
    }
    if (file.exists("scripts/lib/utils.R")) return(normalizePath(".."))
    stop("Cannot locate hfc-agent-skill")
}
skill <- .resolve_skill()
lib <- file.path(skill, "scripts", "lib")
source(file.path(lib, "utils.R"))
source(file.path(lib, "geo_timezone.R"))
source(file.path(lib, "media.R"))
source(file.path(lib, "profile_roles.R"))
source(file.path(lib, "form_logic.R"))
source(file.path(lib, "run_checks.R"))
source(file.path(lib, "balance_tables.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "report_contract.R"))
source(file.path(lib, "validate_config.R"))
source(file.path(lib, "module_desc.R"))
source(file.path(lib, "check_modules_preview.R"))
source(file.path(lib, "pipeline_core.R"))
source(file.path(lib, "product_structure.R"))
source(file.path(lib, "sync_fpaths.R"))
source(file.path(lib, "issue_store.R"))

args <- commandArgs(trailingOnly = TRUE)
do_open <- "--open" %in% args
sample_n <- NA_integer_
if ("--sample" %in% args) {
    i <- match("--sample", args)
    if (!is.na(i) && i < length(args)) sample_n <- as.integer(args[[i + 1]])
}

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

cfg_ctx <- require_hfc_config_ready(skill)
cfg <- cfg_ctx$cfg

message("Input data dir: ", cfg$input_data_dir)
message("Code output dir: ", cfg$code_output_dir)
ensure_project_dirs(cfg$code_output_dir)

# role_map.yaml is the agent's own determination of every structural field
# (see references/role_map_schema.md) — written before this script ever
# runs, via scripts/profile_dataset.R's data profile. Nothing here detects
# or guesses any of it.
role_map_path <- hfc_path(cfg$code_output_dir, "config", "role_map.yaml")
if (!file.exists(role_map_path)) {
    stop(
        "role_map.yaml not found at ", role_map_path, " — run scripts/profile_dataset.R, ",
        "determine every structural field from its output, and write role_map.yaml before building."
    )
}
roles <- yaml::read_yaml(role_map_path)

data_path <- roles$data_file_path %||% NA_character_
if (is.na(data_path) || !nzchar(data_path) || !file.exists(data_path)) {
    stop("role_map.yaml's data_file_path is missing or doesn't exist: ", data_path %||% "(unset)")
}
form_path <- roles$form_file_path %||% NA_character_

# Copy the form into hfc/instruments/form.xlsx (microdata itself stays in place).
if (!is.na(form_path) && file.exists(form_path)) {
    form_dest <- hfc_path(cfg$code_output_dir, "instruments", "form.xlsx")
    if (!identical(normalizePath(form_path, mustWork = FALSE),
                    normalizePath(form_dest, mustWork = FALSE))) {
    file.copy(form_path, form_dest, overwrite = TRUE)
    }
}

message("Loading: ", data_path)
ds <- load_microdata(data_path, sample_n = sample_n)

media_folder <- cfg$media_dir %||% NA_character_
if (!is.na(media_folder) && nzchar(media_folder)) {
    message("Media folder: ", media_folder)
} else {
    message("Media folder: (not configured — M13 on-disk checks will be skipped if media cols exist)")
}

# Fills in the handful of fields that must be recomputed fresh from the data
# every run (completion signal, unique submission key, weekend default, last
# date seen, has_* booleans) on top of the agent-authored roles above.
roles <- profile_roles(ds, roles, media_folder = media_folder)

# Load confirmed module config if it exists, else fall back to defaults.
modules_path <- hfc_path(cfg$code_output_dir, "config", "modules.yaml")
if (file.exists(modules_path)) {
    modules <- yaml::read_yaml(modules_path)
} else {
    modules <- default_modules(roles)
    write_commented_modules_yaml(modules, modules_path)
}
if (!is.null(modules$M2)) {
    modules$M2$id <- roles$entity_id
    modules$M2$extra_keys <- roles$dup_key_extra %||% character()
}
yaml::write_yaml(roles, role_map_path)

form_map <- parse_form_relevance(if (!is.na(form_path) && file.exists(form_path)) form_path else
    hfc_path(cfg$code_output_dir, "instruments", "form.xlsx"))
attr(ds, "hfc_form_map") <- form_map

report_cfg <- list(map_focus = roles$map_focus %||% "country")

module_notes_path <- hfc_path(cfg$code_output_dir, "config", "module_notes.yaml")
module_notes <- if (file.exists(module_notes_path)) yaml::read_yaml(module_notes_path) else NULL

# Load the roster/target-sample list, if one was found.
target_ds <- NULL
if (!is.null(roles$completion_roster_candidate) && !is.na(roles$completion_roster_candidate$path %||% NA_character_)) {
    target_ds <- tryCatch(load_microdata(roles$completion_roster_candidate$path), error = function(e) NULL)
    if (is.null(target_ds)) message("Could not load roster/target file: ", roles$completion_roster_candidate$path)
}

format_config_validation(validate_modules_config(modules, roles, ds = ds), stop_on_error = TRUE)

res <- run_checks_and_write_issues(cfg$code_output_dir, ds, roles, modules, skill, target_ds = target_ds)
findings <- res$findings
stats <- res$stats

# Fetch the live issue_tracking.xlsx and write a pending merge file — the
# live file is only ever updated after you confirm at the final review.
entity_label <- roles$entity_label %||% NA_character_
group_label <- roles$group_label %||% NA_character_
ctx <- fetch_issue_tracking(skill_dir = skill, entity_label = entity_label, group_label = group_label)
fb_new <- findings_to_issue_tracking(findings, roles = roles)
write_tracking_snapshot(ctx, fb_new, entity_label = entity_label, group_label = group_label)

if (!is.null(ctx$tbl)) {
    # Drop any finding already marked Resolved (or no longer tracked) from
    # what the report displays — the live file itself keeps full history.
    findings <- filter_findings_by_tracking_status(findings, ctx$tbl)
    message("Findings after dropping Resolved/untracked: ", nrow(findings), " of ", nrow(res$findings))
}
merged <- merge_preserve_existing(ctx$tbl, fb_new)
write_named_tracking_file(ctx, merged, "merged_issue_tracking.xlsx", entity_label = entity_label, group_label = group_label)
merge_pending <- TRUE

# Mirror config.json into hfc/ for the record.
cfg_dest <- hfc_path(cfg$code_output_dir, "config", "config.json")
dir.create(dirname(cfg_dest), showWarnings = FALSE, recursive = TRUE)
if (!identical(normalizePath(cfg$path, mustWork = FALSE),
                normalizePath(cfg_dest, mustWork = FALSE))) {
    file.copy(cfg$path, cfg_dest, overwrite = TRUE)
}

project_id <- derive_project_id(cfg$input_data_dir)
proj_yaml <- list(
    project_id = project_id,
    data_file = basename(data_path),
    instrument = if (!is.na(form_path)) "hfc/instruments/form.xlsx" else NULL,
    report_type = "html",
    map_focus = report_cfg$map_focus %||% "country",
    shiny_later = TRUE,
    issue_tracking_merge_pending = merge_pending,
    config_file = "config.json",
    created = as.character(Sys.time()),
    n_findings = nrow(findings)
)

html_path <- write_html_report(
    findings, cfg$code_output_dir, project_id, open = do_open,
    roles = roles, ds = ds, report_cfg = report_cfg, module_notes = module_notes,
    stats = stats, modules = modules, target_ds = target_ds
)
tryCatch({
    modules_present <- compute_modules_present(findings, stats, modules)
    v <- validate_report_contract(html_path, file.path(skill, "assets", "report_sections.json"), modules_present, modules)
    message(format_report_contract(v))
}, error = function(e) message("Report contract check skipped: ", e$message))

structure_path <- hfc_path(cfg$code_output_dir, "structure.html")
structure_was_first <- !file.exists(structure_path)
write_product_structure_html(cfg, open = FALSE)

report_copy <- copy_report_to_sync_folder(project_id, skill_dir = skill, html_path)
yaml::write_yaml(proj_yaml, hfc_path(cfg$code_output_dir, "project.yaml"))

message("Done. HTML: ", html_path)
message("Product root: ", hfc_root(cfg$code_output_dir))
message("Structure: ", structure_path, " (first_setup=", structure_was_first, ")")
message("Issue tracking folder: ", ctx$local_dir %||% "(unavailable)", " (", ctx$reason %||% "", ")")
message("MERGE_PENDING: review merged_issue_tracking.xlsx, then after the final approval gate:")
message("  Rscript .claude/skills/hfc-agent-skill/scripts/commit_merged_issue_tracking.R merged_issue_tracking.xlsx")
message("Report copy: ", report_copy$status, " (", report_copy$reason %||% "", ") ", report_copy$dest_path %||% "(none)")
message("When field edits issue_tracking, run: Process HFC feedback")

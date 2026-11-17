# Refreshes the HTML report after a "Process HFC feedback" pass — re-runs
# every check against the latest (fixed) data, using the already-confirmed
# config, and drops any finding already marked Resolved.
#
# Usage: Rscript rebuild_report.R [--open]

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
source(file.path(lib, "form_logic.R"))
source(file.path(lib, "run_checks.R"))
source(file.path(lib, "balance_tables.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "report_contract.R"))
source(file.path(lib, "validate_config.R"))
source(file.path(lib, "module_desc.R"))
source(file.path(lib, "pipeline_core.R"))
source(file.path(lib, "sync_fpaths.R"))
source(file.path(lib, "issue_store.R"))

args <- commandArgs(trailingOnly = TRUE)
do_open <- "--open" %in% args

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

cfg_ctx <- require_hfc_config_ready(skill)
cfg <- cfg_ctx$cfg

role_map_path <- hfc_path(cfg$code_output_dir, "config", "role_map.yaml")
modules_path <- hfc_path(cfg$code_output_dir, "config", "modules.yaml")
proj_yaml_path <- hfc_path(cfg$code_output_dir, "project.yaml")
if (!file.exists(role_map_path) || !file.exists(modules_path) || !file.exists(proj_yaml_path)) {
    stop(
    "No prior build found (missing role_map.yaml / modules.yaml / project.yaml under hfc/config or hfc/) — ",
    "run the setup build first: Rscript run_setup_build.R"
    )
}

roles <- yaml::read_yaml(role_map_path)
modules <- yaml::read_yaml(modules_path)
proj_yaml <- yaml::read_yaml(proj_yaml_path)
data_rel <- proj_yaml$data_file
project_id <- proj_yaml$project_id %||% derive_project_id(cfg$input_data_dir)
entity_label <- roles$entity_label %||% NA_character_
group_label <- roles$group_label %||% NA_character_

message("Loading latest data for: ", cfg$input_data_dir)
ds <- load_latest_dataset(cfg$input_data_dir, cfg$onedrive_output_dir, data_rel)

form_path <- hfc_path(cfg$code_output_dir, "instruments", "form.xlsx")
if (file.exists(form_path) && exists("parse_form_relevance", mode = "function")) {
    attr(ds, "hfc_form_map") <- parse_form_relevance(form_path)
}

module_notes_path <- hfc_path(cfg$code_output_dir, "config", "module_notes.yaml")
module_notes <- if (file.exists(module_notes_path)) yaml::read_yaml(module_notes_path) else NULL

# Reload the roster/target-sample list, if one was found.
target_ds <- NULL
if (!is.null(roles$completion_roster_candidate) && !is.na(roles$completion_roster_candidate$path %||% NA_character_)) {
    target_ds <- tryCatch(load_microdata(roles$completion_roster_candidate$path), error = function(e) NULL)
}

format_config_validation(validate_modules_config(modules, roles, ds = ds), stop_on_error = TRUE)

res <- run_checks_and_write_issues(cfg$code_output_dir, ds, roles, modules, skill, target_ds = target_ds)

ctx <- fetch_issue_tracking(skill_dir = skill, entity_label = entity_label, group_label = group_label)
if (is.null(ctx$tbl)) {
    stop("No issue_tracking.xlsx found in the configured OneDrive output folder — nothing to filter the report against. Run the setup build first.")
}

fb_fresh <- findings_to_issue_tracking(res$findings, roles = roles)
write_tracking_snapshot(ctx, fb_fresh, entity_label = entity_label, group_label = group_label)

# Refresh ONLY the derived Completion sheet in the live file against the
# latest (fixed) data - the Tracking sheet is never touched here.
tryCatch({
    existing_completion <- read_completion_sheet(ctx, ctx$dest_name)
    completion_tbl <- build_completion_table(ds, roles, modules, target_ds = target_ds, existing = existing_completion)
    if (!is.null(completion_tbl)) {
        refresh_completion_sheet(ctx, ctx$dest_name, completion_tbl)
        message("Completion sheet refreshed (", nrow(completion_tbl), " rows).")
    }
}, error = function(e) message("Completion sheet not refreshed: ", e$message))

filtered <- filter_findings_by_tracking_status(res$findings, ctx$tbl)
message("Findings after dropping Resolved/untracked: ", nrow(filtered), " of ", nrow(res$findings))

report_cfg <- list(map_focus = roles$map_focus %||% "country")
html_path <- write_html_report(
    filtered, cfg$code_output_dir, project_id, open = do_open,
    roles = roles, ds = ds, report_cfg = report_cfg, module_notes = module_notes,
    stats = res$stats, modules = modules, target_ds = target_ds
)
tryCatch({
    modules_present <- compute_modules_present(filtered, res$stats, modules)
    v <- validate_report_contract(html_path, file.path(skill, "assets", "report_sections.json"), modules_present, modules)
    message(format_report_contract(v))
}, error = function(e) message("Report contract check skipped: ", e$message))

report_copy <- copy_report_to_sync_folder(project_id, skill_dir = skill, html_path)

message("Done. HTML: ", html_path)
message("Report copy: ", report_copy$status, " (", report_copy$reason %||% "", ") ", report_copy$dest_path %||% "(none)")

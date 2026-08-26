# Writes hfc/config/modules.yaml — a commented, editable draft of every
# check's proposed settings — for you to review before confirming.
#
# Usage: Rscript preview_modules.R

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
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "module_desc.R"))
source(file.path(lib, "check_modules_preview.R"))
source(file.path(lib, "sync_fpaths.R"))
source(file.path(lib, "issue_store.R"))

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

ctx <- require_hfc_config_ready(skill)
cfg <- ctx$cfg
modules_path <- hfc_path(cfg$code_output_dir, "config", "modules.yaml")

# --blank: write an empty, pre-fillable draft before any data is loaded, so
# you can hand-edit anything you already know up front.
args <- commandArgs(trailingOnly = TRUE)
if ("--blank" %in% args) {
    out <- write_commented_modules_yaml(list(), modules_path)
    message("Wrote blank draft: ", out)
    quit(save = "no", status = 0)
}

# role_map.yaml is the agent's own determination of every structural field
# (see references/role_map_schema.md), written via scripts/profile_dataset.R
# before this script ever runs.
role_map_path <- hfc_path(cfg$code_output_dir, "config", "role_map.yaml")
if (!file.exists(role_map_path)) {
    stop(
        "role_map.yaml not found at ", role_map_path, " — run scripts/profile_dataset.R, ",
        "determine every structural field from its output, and write role_map.yaml first."
    )
}
roles <- yaml::read_yaml(role_map_path)

data_path <- roles$data_file_path %||% NA_character_
if (is.na(data_path) || !nzchar(data_path) || !file.exists(data_path)) {
    stop("role_map.yaml's data_file_path is missing or doesn't exist: ", data_path %||% "(unset)")
}

message("Loading: ", data_path)
ds <- load_microdata(data_path)

media_folder <- cfg$media_dir %||% NA_character_
roles <- profile_roles(ds, roles, media_folder = media_folder)

# Merge fresh defaults with whatever's already on disk (a hand-edited draft).
guessed <- default_modules(roles)
prefilled <- if (file.exists(modules_path)) yaml::read_yaml(modules_path) else list()
modules <- merge_prefilled_modules(guessed, prefilled)

out <- write_commented_modules_yaml(modules, modules_path)
message("Wrote ", out)

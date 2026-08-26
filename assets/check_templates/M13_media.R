# M13 (Media Files) check, standalone — same logic as the report.
# Usage: Rscript hfc/code/checks/M13_media.R
#
# Unlike every other module's check_mN(), which returns list(findings=,
# stats=), run_m13_media_checks() (scripts/lib/media.R) returns a bare
# findings tibble directly — hence `findings <- run_m13_media_checks(...)`
# below instead of `res <- check_m13(...); res$findings`.

# Filled in automatically — leave as-is unless running this by hand.
skill <- "your/path/to/hfc-agent-skill/"
code_output_dir <- "your/path/to/hfc/output/"

run_m13_media_check <- function() {
  lib <- file.path(skill, "scripts", "lib")
  for (f in c("utils.R", "geo_timezone.R", "media.R", "form_logic.R", "profile_roles.R", "run_checks.R", "sync_fpaths.R")) {
    source(file.path(lib, f))
  }
  suppressPackageStartupMessages({ library(dplyr); library(yaml) })

  cfg <- load_hfc_config(skill)
  if (!isTRUE(cfg$found)) stop("skills/hfc-agent-skill/config.json is not fully configured. Reason: ", cfg$reason)

  roles <- yaml::read_yaml(hfc_path(code_output_dir, "config", "role_map.yaml"))
  modules <- yaml::read_yaml(hfc_path(code_output_dir, "config", "modules.yaml"))
  proj_yaml <- yaml::read_yaml(hfc_path(code_output_dir, "project.yaml"))
  ds <- load_latest_dataset(cfg$input_data_dir, cfg$onedrive_output_dir, proj_yaml$data_file)
  ds <- prepare_ds_for_checks(ds, roles, code_output_dir, modules = modules)
  ds <- ds_for_module_selection(ds, "M13", modules)

  findings <- run_m13_media_checks(ds, roles, modules)
  findings <- dedupe_finding_ids(findings)
  message("M13 (Media Files): ", nrow(findings), " findings")
  print(as.data.frame(findings))
}

.args <- commandArgs(trailingOnly = FALSE)
.file <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
if (length(.file) && grepl("M13_media\\.R$", .file[[1]])) run_m13_media_check()

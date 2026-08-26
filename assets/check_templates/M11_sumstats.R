# M11 (Summary Statistics) check, standalone — same logic as the report.
# Usage: Rscript hfc/code/checks/M11_sumstats.R

# Filled in automatically — leave as-is unless running this by hand.
skill <- "your/path/to/hfc-agent-skill/"
code_output_dir <- "your/path/to/hfc/output/"

run_m11_sumstats_check <- function() {
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
  ds <- ds_for_module_selection(ds, "M11", modules)

  res <- check_m11(ds, roles, modules)
  message("M11 (Summary Statistics) — descriptive only, never produces findings rows:")
  print(res$stats)
}

.args <- commandArgs(trailingOnly = FALSE)
.file <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
if (length(.file) && grepl("M11_sumstats\\.R$", .file[[1]])) run_m11_sumstats_check()

# Post-feedback helpers. Every row with Status "Open" and a non-empty
# Comment is picked up; the agent interprets the comment and applies the
# fix. All work happens against today's resolutions clone — the live
# issue_tracking.xlsx is only ever updated after you confirm the merge.

sanitize_finding_id <- function(finding_id) gsub("[^A-Za-z0-9_.-]", "_", finding_id)

#' Creates today's resolutions clone (reused if one already exists today).
clone_for_resolution_pass <- function(cfg, skill_dir = NULL, date = Sys.Date()) {
  entity_label <- load_entity_label(cfg$code_output_dir)
  group_label <- load_group_label(cfg$code_output_dir)
  ctx <- fetch_issue_tracking(skill_dir = skill_dir, entity_label = entity_label, group_label = group_label)
  existing <- read_resolution_clone(ctx, date = date, entity_label = entity_label, group_label = group_label)
  if (!is.null(existing)) {
    return(list(status = "reused", n = nrow(existing)))
  }
  if (is.null(ctx$tbl)) stop("No issue_tracking.xlsx found — run the setup build first.")
  write_resolution_clone(ctx, ctx$tbl, date = date, entity_label = entity_label, group_label = group_label)
  list(status = "created", n = nrow(ctx$tbl))
}

#' Open rows with a comment from today's resolutions clone.
list_open_commented_rows <- function(cfg, skill_dir = NULL, date = Sys.Date()) {
  suppressPackageStartupMessages({ library(dplyr) })
  entity_label <- load_entity_label(cfg$code_output_dir)
  group_label <- load_group_label(cfg$code_output_dir)
  ctx <- fetch_issue_tracking(skill_dir = skill_dir, entity_label = entity_label, group_label = group_label)
  clone <- read_resolution_clone(ctx, date = date, entity_label = entity_label, group_label = group_label)
  if (is.null(clone)) stop("No resolutions/ clone for today — run clone_for_resolution_pass() first.")
  clone %>% filter(toupper(as.character(status)) == "OPEN", nzchar(as.character(comment)))
}

#' Update one row's Status/Corrections in today's resolutions clone only.
.update_clone_row <- function(cfg, skill_dir, date, finding_id, new_status, corrections_text = NULL) {
  entity_label <- load_entity_label(cfg$code_output_dir)
  group_label <- load_group_label(cfg$code_output_dir)
  ctx <- fetch_issue_tracking(skill_dir = skill_dir, entity_label = entity_label, group_label = group_label)
  clone <- read_resolution_clone(ctx, date = date, entity_label = entity_label, group_label = group_label)
  if (is.null(clone)) stop("No resolutions/ clone for today — run clone_for_resolution_pass() first.")
  if (!finding_id %in% clone$finding_id) stop("Issue ID not found in today's resolutions clone: ", finding_id)
  clone$status[clone$finding_id == finding_id] <- new_status
  if (!is.null(corrections_text)) {
    clone$corrections[clone$finding_id == finding_id] <- corrections_text
  }
  write_resolution_clone(ctx, clone, date = date, entity_label = entity_label, group_label = group_label)
  record_touched_id(ctx, finding_id, date = date)
  invisible(clone)
}

#' Applies one fix (hfc/code/resolutions/<id>.R) to the data, and marks the
#' row Resolved in today's clone. Safe to retry if interrupted partway.
apply_one_fix <- function(cfg, finding_id, corrections_text, skill_dir = NULL, date = Sys.Date()) {
  fixes_dir <- hfc_path(cfg$code_output_dir, "code", "resolutions")
  fix_file <- file.path(fixes_dir, paste0(sanitize_finding_id(finding_id), ".R"))
  if (!file.exists(fix_file)) {
    stop("No fix file found: ", fix_file, " — write it first, defining fix(ds) -> ds.")
  }

  ctx <- fetch_issue_tracking(skill_dir = skill_dir)
  if (is_fix_applied(ctx, finding_id, date = date)) {
    .update_clone_row(cfg, skill_dir, date, finding_id, "Resolved", corrections_text)
    return(list(status = "already_applied", updated_data_path = NA_character_, fix_file = fix_file))
  }

  env <- new.env(parent = globalenv())
  sys.source(fix_file, envir = env)
  if (!exists("fix", envir = env, mode = "function")) {
    stop("Fix file must define fix(ds): ", fix_file)
  }

  proj_yaml_path <- hfc_path(cfg$code_output_dir, "project.yaml")
  proj <- yaml::read_yaml(proj_yaml_path)
  data_rel <- proj$data_file
  stem <- tools::file_path_sans_ext(basename(data_rel))
  ext <- tolower(tools::file_ext(data_rel))

  ds <- load_latest_dataset(cfg$input_data_dir, cfg$onedrive_output_dir, data_rel)
  fixed_ds <- env$fix(ds)
  out_path <- write_intermediate(fixed_ds, cfg$onedrive_output_dir, stem, ext)
  record_fix_applied(ctx, finding_id, date = date)

  .update_clone_row(cfg, skill_dir, date, finding_id, "Resolved", corrections_text)

  list(status = "ok", updated_data_path = out_path, fix_file = fix_file)
}

#' The agent couldn't confidently resolve this row — mark it for human
#' follow-up instead of leaving it stuck on Open.
mark_needs_review <- function(cfg, finding_id, skill_dir = NULL, date = Sys.Date()) {
  .update_clone_row(cfg, skill_dir, date, finding_id, "Needs Review")
  list(status = "ok")
}

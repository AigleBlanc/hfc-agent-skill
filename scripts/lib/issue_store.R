# Reads and writes issue_tracking.xlsx in your configured OneDrive folder —
# the one shared store, no separate local copy.
#
# Subfolders alongside the live file:
#   intermediate/<YYYYMMDD>_issue_tracking.xlsx   — one per setup-build run
#   resolutions/<YYYYMMDD>_issues_resolution.xlsx — one clone per feedback day

resolve_tracking_ctx <- function(skill_dir = NULL) {
  if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess()
  cfg <- load_hfc_config(skill_dir)
  if (!isTRUE(cfg$found)) {
    return(list(ready = FALSE, cfg = cfg, local_dir = NA_character_, reason = cfg$reason %||% "config_unavailable"))
  }
  ensure_local_folder(cfg$onedrive_output_dir)
  if (!dir.exists(cfg$onedrive_output_dir)) {
    return(list(ready = FALSE, cfg = cfg, local_dir = NA_character_, reason = "onedrive_output_dir_not_creatable"))
  }
  list(ready = TRUE, cfg = cfg, local_dir = cfg$onedrive_output_dir, reason = "ok")
}

#' Stops with setup instructions if config.json isn't fully configured yet.
require_hfc_config_ready <- function(skill_dir = NULL) {
  ctx <- resolve_tracking_ctx(skill_dir)
  if (!isTRUE(ctx$ready)) {
    stop(
      "skills/hfc-agent-skill/config.json must be fully configured before running HFCs.\n",
      "  1. Rscript <skill_dir>/install.R\n",
      "  2. Make sure OneDrive's desktop app is installed and signed in on this machine, and note the local folder it syncs to.\n",
      "  3. Edit <skill_dir>/config.json: set input_data_dir, onedrive_output_dir, and code_output_dir (media_dir is optional).\n",
      "Reason it wasn't ready just now: ", ctx$reason %||% "unknown"
    )
  }
  ctx
}

.tracking_subfolder <- function(ctx, subfolder) {
  dir <- file.path(ctx$local_dir, subfolder)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir
}

#' Reads a named tracking-shaped xlsx (or NULL if it doesn't exist yet).
read_named_tracking_file <- function(ctx, dest_name, subfolder = NULL, entity_label = NA_character_, group_label = NA_character_) {
  dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
  path <- file.path(dir, dest_name)
  if (!file.exists(path)) return(NULL)
  read_issue_tracking(path, entity_label = entity_label, group_label = group_label)
}

COMPLETION_SHEET <- "Completion"

# Makes submitted/completed real integers (a read-back from xlsx can leave
# them as strings) before writing the Completion sheet.
as_completion_sheet <- function(tbl) {
  tbl <- as.data.frame(tbl, stringsAsFactors = FALSE, check.names = FALSE)
  for (cn in intersect(c("submitted", "completed"), names(tbl))) {
    tbl[[cn]] <- suppressWarnings(as.integer(tbl[[cn]]))
  }
  tbl
}

#' Reads the "Completion" sheet from an xlsx path; NULL if the file or the
#' sheet doesn't exist (or it's empty).
read_completion_path <- function(path) {
  if (!file.exists(path)) return(NULL)
  sheets <- tryCatch(openxlsx::getSheetNames(path), error = function(e) character())
  if (!COMPLETION_SHEET %in% sheets) return(NULL)
  tbl <- read_xlsx_verbatim_headers(path, COMPLETION_SHEET)
  if (!nrow(tbl) || !ncol(tbl)) return(NULL)
  tbl
}

#' Reads the Completion sheet of a named tracking file (NULL if none).
read_completion_sheet <- function(ctx, dest_name, subfolder = NULL) {
  dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
  read_completion_path(file.path(dir, dest_name))
}

#' Replaces ONLY the Completion sheet in an existing tracking file (the
#' Tracking sheet is left exactly as it is). Same temp-file-then-rename
#' write as write_named_tracking_file().
refresh_completion_sheet <- function(ctx, dest_name, completion_tbl, subfolder = NULL) {
  dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
  xlsx_path <- file.path(dir, dest_name)
  if (!file.exists(xlsx_path)) stop("refresh_completion_sheet(): no file at ", xlsx_path)
  suppressPackageStartupMessages(library(openxlsx))
  wb <- loadWorkbook(xlsx_path)
  if (COMPLETION_SHEET %in% names(wb)) removeWorksheet(wb, COMPLETION_SHEET)
  addWorksheet(wb, COMPLETION_SHEET)
  writeData(wb, COMPLETION_SHEET, as_completion_sheet(completion_tbl))
  tmp_path <- file.path(dir, paste0(".", basename(dest_name), ".", Sys.getpid(), ".tmp"))
  saveWorkbook(wb, tmp_path, overwrite = TRUE)
  if (!file.rename(tmp_path, xlsx_path)) {
    file.copy(tmp_path, xlsx_path, overwrite = TRUE)
    file.remove(tmp_path)
  }
  list(status = "ok", path = xlsx_path)
}

#' Writes a tracking-shaped tibble as `dest_name`. Writes to a temp file
#' first, then renames it into place, so an interruption mid-write can
#' never leave the file corrupted.
#'
#' `completion` controls the second "Completion" sheet: NULL = none, a
#' data.frame = write it, "keep" (default) = carry over whatever Completion
#' sheet already sits in the destination file, so a Tracking-only write
#' (patch_tracking_cells(), a merge, a commit) never wipes it.
write_named_tracking_file <- function(ctx, tbl, dest_name, subfolder = NULL, entity_label = NA_character_, group_label = NA_character_, completion = "keep") {
  dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
  xlsx_path <- file.path(dir, dest_name)
  display <- prepare_tracking_display(tbl, entity_label, group_label)
  suppressPackageStartupMessages(library(openxlsx))
  if (is.character(completion) && identical(completion, "keep")) {
    completion <- read_completion_path(xlsx_path)
  }
  wb <- createWorkbook(); addWorksheet(wb, "Tracking")
  writeData(wb, "Tracking", display)
  if (is.data.frame(completion) && ncol(completion) > 0) {
    addWorksheet(wb, COMPLETION_SHEET)
    writeData(wb, COMPLETION_SHEET, as_completion_sheet(completion))
  }
  tmp_path <- file.path(dir, paste0(".", basename(dest_name), ".", Sys.getpid(), ".tmp"))
  saveWorkbook(wb, tmp_path, overwrite = TRUE)
  if (!file.rename(tmp_path, xlsx_path)) {
    file.copy(tmp_path, xlsx_path, overwrite = TRUE)
    file.remove(tmp_path)
  }
  list(status = "ok", path = xlsx_path)
}

#' Checks a tracking table looks intact: expected row count, no blank or
#' duplicate finding_id (the key the merge system depends on).
verify_tracking_integrity <- function(tbl, expect_n = NULL) {
  if (is.null(tbl)) stop("verify_tracking_integrity(): tbl is NULL.")
  if (!"finding_id" %in% names(tbl)) stop("verify_tracking_integrity(): tbl has no finding_id column.")
  if (!is.null(expect_n) && nrow(tbl) != expect_n) {
    stop(sprintf("verify_tracking_integrity(): row count is %d, expected %d — a write may have been truncated.", nrow(tbl), expect_n))
  }
  fid <- as.character(tbl$finding_id)
  blank <- is.na(fid) | !nzchar(fid)
  if (any(blank)) {
    stop(sprintf("verify_tracking_integrity(): %d row(s) have a blank finding_id — the join key the merge system depends on.", sum(blank)))
  }
  dup <- unique(fid[duplicated(fid)])
  if (length(dup)) {
    stop(sprintf("verify_tracking_integrity(): duplicate finding_id(s): %s", paste(dup, collapse = ", ")))
  }
  invisible(TRUE)
}

#' Patches specific cells in the live tracking file by finding_id, leaving
#' everything else untouched. Errors on an unknown finding_id rather than
#' silently doing nothing.
patch_tracking_cells <- function(ctx, dest_name, updates, subfolder = NULL, entity_label = NA_character_, group_label = NA_character_) {
  if (!is.data.frame(updates) || !"finding_id" %in% names(updates)) {
    stop("patch_tracking_cells(): `updates` must be a data.frame with a finding_id column.")
  }
  current <- read_named_tracking_file(ctx, dest_name, subfolder = subfolder, entity_label = entity_label, group_label = group_label)
  if (is.null(current)) stop("patch_tracking_cells(): no existing file at ", dest_name, " to patch.")
  verify_tracking_integrity(current)
  patch_cols <- intersect(setdiff(names(updates), "finding_id"), names(current))
  if (!length(patch_cols)) {
    stop("patch_tracking_cells(): no patchable columns in common between `updates` and the live table.")
  }
  unknown_ids <- setdiff(as.character(updates$finding_id), as.character(current$finding_id))
  if (length(unknown_ids)) {
    stop("patch_tracking_cells(): finding_id(s) not present in the live table: ", paste(unknown_ids, collapse = ", "))
  }
  match_idx <- match(as.character(updates$finding_id), as.character(current$finding_id))
  for (col in patch_cols) {
    current[[col]][match_idx] <- updates[[col]]
  }
  n_before <- nrow(current)
  verify_tracking_integrity(current, expect_n = n_before)
  write_named_tracking_file(ctx, current, dest_name, subfolder = subfolder, entity_label = entity_label, group_label = group_label)
}

#' Deletes a named file — used after a merged_*.xlsx has been committed.
delete_named_tracking_file <- function(ctx, dest_name, subfolder = NULL) {
  dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
  path <- file.path(dir, dest_name)
  if (file.exists(path)) file.remove(path)
  invisible(NULL)
}

#' Fetches the current live issue_tracking.xlsx. `tbl` is NULL on a
#' first-ever run.
fetch_issue_tracking <- function(skill_dir = NULL, entity_label = NA_character_, group_label = NA_character_) {
  ctx <- resolve_tracking_ctx(skill_dir)
  dest_name <- ctx$cfg$main_file %||% "issue_tracking.xlsx"
  tbl <- read_named_tracking_file(ctx, dest_name, entity_label = entity_label, group_label = group_label)
  c(ctx, list(tbl = tbl, dest_name = dest_name))
}

#' Commits tbl as the live issue_tracking.xlsx.
commit_issue_tracking <- function(tbl, skill_dir = NULL, fetch_ctx = NULL, entity_label = NA_character_, group_label = NA_character_, completion = "keep") {
  ctx <- fetch_ctx %||% resolve_tracking_ctx(skill_dir)
  dest_name <- ctx$cfg$main_file %||% "issue_tracking.xlsx"
  verify_tracking_integrity(tbl)
  write_named_tracking_file(ctx, tbl, dest_name, entity_label = entity_label, group_label = group_label, completion = completion)
}

snapshot_tracking_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_issue_tracking.xlsx")
snapshot_resolution_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_issues_resolution.xlsx")

#' Write/read today's intermediate/ snapshot (one per setup-build run).
write_tracking_snapshot <- function(ctx, tbl, date = Sys.Date(), entity_label = NA_character_, group_label = NA_character_, completion = "keep") {
  write_named_tracking_file(ctx, tbl, snapshot_tracking_filename(date), subfolder = "intermediate", entity_label = entity_label, group_label = group_label, completion = completion)
}
read_tracking_snapshot <- function(ctx, date = Sys.Date(), entity_label = NA_character_, group_label = NA_character_) {
  read_named_tracking_file(ctx, snapshot_tracking_filename(date), subfolder = "intermediate", entity_label = entity_label, group_label = group_label)
}

#' Write/read today's resolutions/ clone (one working copy per feedback day).
write_resolution_clone <- function(ctx, tbl, date = Sys.Date(), entity_label = NA_character_, group_label = NA_character_) {
  write_named_tracking_file(ctx, tbl, snapshot_resolution_filename(date), subfolder = "resolutions", entity_label = entity_label, group_label = group_label)
}
read_resolution_clone <- function(ctx, date = Sys.Date(), entity_label = NA_character_, group_label = NA_character_) {
  read_named_tracking_file(ctx, snapshot_resolution_filename(date), subfolder = "resolutions", entity_label = entity_label, group_label = group_label)
}

touched_ids_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_touched_ids.txt")

#' Records that finding_id was actually changed in today's resolutions
#' pass, so a later merge only overwrites rows genuinely touched today —
#' never a row a field/RA edit reached concurrently.
record_touched_id <- function(ctx, finding_id, date = Sys.Date()) {
  dir <- .tracking_subfolder(ctx, "resolutions")
  path <- file.path(dir, touched_ids_filename(date))
  cat(finding_id, "\n", file = path, append = TRUE, sep = "")
  invisible(NULL)
}

#' Every finding_id actually touched during today's resolution pass.
read_touched_ids <- function(ctx, date = Sys.Date()) {
  dir <- .tracking_subfolder(ctx, "resolutions")
  path <- file.path(dir, touched_ids_filename(date))
  if (!file.exists(path)) return(character(0))
  ids <- readLines(path, warn = FALSE)
  unique(ids[nzchar(ids)])
}

applied_ids_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_applied_ids.txt")

#' Records that finding_id's fix has been applied to the data today —
#' guards against double-applying it on a retry after an interruption.
record_fix_applied <- function(ctx, finding_id, date = Sys.Date()) {
  dir <- .tracking_subfolder(ctx, "resolutions")
  path <- file.path(dir, applied_ids_filename(date))
  cat(finding_id, "\n", file = path, append = TRUE, sep = "")
  invisible(NULL)
}

#' Has finding_id's fix already been applied today?
is_fix_applied <- function(ctx, finding_id, date = Sys.Date()) {
  dir <- .tracking_subfolder(ctx, "resolutions")
  path <- file.path(dir, applied_ids_filename(date))
  if (!file.exists(path)) return(FALSE)
  ids <- readLines(path, warn = FALSE)
  finding_id %in% ids[nzchar(ids)]
}

#' Loads a project's configured entity_label. NA if missing.
load_entity_label <- function(code_output_dir) {
  path <- hfc_path(code_output_dir, "config", "role_map.yaml")
  if (!file.exists(path)) return(NA_character_)
  cfg <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  lbl <- cfg$entity_label
  if (is.null(lbl) || !nzchar(as.character(lbl))) return(NA_character_)
  as.character(lbl)
}

#' Loads a project's configured group_label. NA if missing.
load_group_label <- function(code_output_dir) {
  path <- hfc_path(code_output_dir, "config", "role_map.yaml")
  if (!file.exists(path)) return(NA_character_)
  cfg <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  lbl <- cfg$group_label
  if (is.null(lbl) || !nzchar(as.character(lbl))) return(NA_character_)
  as.character(lbl)
}

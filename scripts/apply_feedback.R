# Post-feedback pipeline. Any row with Status=Open and a non-empty Comment
# is eligible; fixes are applied against today's resolutions clone, never
# issue_tracking.xlsx directly.
#
# Usage:
#   Rscript apply_feedback.R clone
#   Rscript apply_feedback.R list-open
#   Rscript apply_feedback.R apply --finding-id <id> --corrections "<text>"
#   Rscript apply_feedback.R needs-review --finding-id <id>

.resolve_skill <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", ca, value = TRUE)
  sp <- if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
  if (!is.na(sp) && file.exists(sp)) return(normalizePath(file.path(dirname(sp), "..")))
  if (file.exists(".claude/skills/hfc-agent-skill/scripts/lib/utils.R")) return(normalizePath(".claude/skills/hfc-agent-skill"))
  if (file.exists("hfc-agent-skill/scripts/lib/utils.R")) return(normalizePath("hfc-agent-skill"))
  if (file.exists("scripts/lib/utils.R")) return(normalizePath(".."))
  stop("Cannot locate hfc-agent-skill")
}
skill <- .resolve_skill()
lib <- file.path(skill, "scripts", "lib")
source(file.path(lib, "utils.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "sync_fpaths.R"))
source(file.path(lib, "issue_store.R"))
source(file.path(lib, "apply_feedback_helpers.R"))

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  stop("Usage: apply_feedback.R <clone|list-open|apply|needs-review> [--finding-id <id>] [--corrections <text>]")
}
mode <- args[[1]]
rest <- args[-1]
opt_val <- function(flag) {
  i <- match(flag, rest)
  if (!is.na(i) && i < length(rest)) rest[[i + 1]] else NA_character_
}
finding_id <- opt_val("--finding-id")
corrections_text <- opt_val("--corrections")

cfg_ctx <- require_hfc_config_ready(skill)
cfg <- cfg_ctx$cfg

if (mode == "clone") {
  res <- clone_for_resolution_pass(cfg, skill_dir = skill)
  message("Resolutions clone ", res$status, " (", res$n, " rows).")
} else if (mode == "list-open") {
  open_rows <- list_open_commented_rows(cfg, skill_dir = skill)
  out_path <- hfc_path(cfg$code_output_dir, "outputs", "fix_candidates.csv")
  write_csv(open_rows, out_path)
  message("Open + commented rows: ", nrow(open_rows))
  message("Wrote ", out_path)
} else if (mode == "apply") {
  if (is.na(finding_id)) stop("apply requires --finding-id <id>")
  if (is.na(corrections_text)) stop("apply requires --corrections \"<text>\"")
  res <- apply_one_fix(cfg, finding_id, corrections_text, skill_dir = skill)
  message("Fixed ", finding_id, " -> ", res$updated_data_path)
  message("Status set to Resolved in today's resolutions clone.")
} else if (mode == "needs-review") {
  if (is.na(finding_id)) stop("needs-review requires --finding-id <id>")
  mark_needs_review(cfg, finding_id, skill_dir = skill)
  message("Status set to Needs Review for ", finding_id, " in today's resolutions clone.")
} else {
  stop("Unknown mode: ", mode, " (expected clone | list-open | apply | needs-review)")
}

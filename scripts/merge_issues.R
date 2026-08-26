# Merges today's fresh findings into the live issue_tracking.xlsx, writing
# merged_issue_tracking.xlsx alongside it without touching the live file.
# Review it, then run commit_merged_issue_tracking.R to apply it.
#
# Usage: Rscript merge_issues.R

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
source(file.path(lib, "verify_merge.R"))

suppressPackageStartupMessages({ library(dplyr) })

cfg_ctx <- require_hfc_config_ready(skill)
cfg <- cfg_ctx$cfg
entity_label <- load_entity_label(cfg$code_output_dir)
group_label <- load_group_label(cfg$code_output_dir)
ctx <- fetch_issue_tracking(skill_dir = skill, entity_label = entity_label, group_label = group_label)
current <- ctx$tbl

if (is.null(current)) {
  message("No existing issue_tracking.xlsx — nothing to merge (first-ever build writes it directly).")
  quit(save = "no", status = 0)
}

snapshot <- read_tracking_snapshot(ctx, entity_label = entity_label, group_label = group_label)
if (is.null(snapshot)) {
  stop("No snapshot found for today under intermediate/ — run the setup build first.")
}

merged <- merge_preserve_existing(current, snapshot)

v <- verify_findings_merge(current, snapshot, merged)
message(format_merge_verification(v))
if (!isTRUE(v$ok)) {
  stop("merge_issues.R: verification failed — merged_issue_tracking.xlsx NOT written. See the verification output above.")
}

res <- write_named_tracking_file(ctx, merged, "merged_issue_tracking.xlsx", entity_label = entity_label, group_label = group_label)

message("Wrote merged_issue_tracking.xlsx (", nrow(merged), " rows: ", nrow(current), " existing + ",
        nrow(merged) - nrow(current), " new).")
message("Review it, then run commit_merged_issue_tracking.R to replace issue_tracking.xlsx.")

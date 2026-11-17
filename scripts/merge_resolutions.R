# Merges today's Status/Corrections edits back into the live
# issue_tracking.xlsx, writing merged_issue_resolutions.xlsx alongside it
# without touching the live file. Review it, then run
# commit_merged_issue_tracking.R to apply it.
#
# Usage: Rscript merge_resolutions.R

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

cfg_ctx <- require_hfc_config_ready(skill)
cfg <- cfg_ctx$cfg
entity_label <- load_entity_label(cfg$code_output_dir)
group_label <- load_group_label(cfg$code_output_dir)
ctx <- fetch_issue_tracking(skill_dir = skill, entity_label = entity_label, group_label = group_label)
current <- ctx$tbl
if (is.null(current)) stop("No issue_tracking.xlsx found — run the setup build first.")

clone <- read_resolution_clone(ctx, entity_label = entity_label, group_label = group_label)
if (is.null(clone)) {
  stop("No resolutions/ clone found for today — run `apply_feedback.R clone` first.")
}

# Only rows actually touched today get overwritten — protects a concurrent
# field/RA edit to any other row from being clobbered.
touched_ids <- read_touched_ids(ctx)
merged <- merge_resolution_updates(current, clone, touched_ids = touched_ids)

v <- verify_resolution_merge(current, clone, merged)
message(format_merge_verification(v))
if (!isTRUE(v$ok)) {
  stop("merge_resolutions.R: verification failed — merged_issue_resolutions.xlsx NOT written. See the verification output above.")
}

# Carry the live file's Completion sheet through unchanged.
write_named_tracking_file(ctx, merged, "merged_issue_resolutions.xlsx", entity_label = entity_label, group_label = group_label,
                          completion = read_completion_sheet(ctx, ctx$dest_name))

n_changed <- sum(as.character(current$finding_id) %in% touched_ids &
                 current$finding_id %in% clone$finding_id &
                 (current$status != clone$status[match(current$finding_id, clone$finding_id)]))
message("Wrote merged_issue_resolutions.xlsx (", nrow(merged), " rows, ", n_changed, " Status changes from this pass).")
message("Review it, then run commit_merged_issue_tracking.R to replace issue_tracking.xlsx.")

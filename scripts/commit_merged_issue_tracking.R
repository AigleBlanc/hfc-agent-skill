# Overwrites the live issue_tracking.xlsx with an already-reviewed merged
# file, then deletes the merged file. Only ever run after you've confirmed
# the merge.
#
# Usage: Rscript commit_merged_issue_tracking.R <merged_filename>
#   (skills/hfc-agent-skill/config.json must already be configured)
#   e.g. Rscript commit_merged_issue_tracking.R merged_issue_tracking.xlsx
#        Rscript commit_merged_issue_tracking.R merged_issue_resolutions.xlsx

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

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: commit_merged_issue_tracking.R <merged_filename>")
merged_filename <- args[[1]]

cfg_ctx <- require_hfc_config_ready(skill)
cfg <- cfg_ctx$cfg
entity_label <- load_entity_label(cfg$code_output_dir)
group_label <- load_group_label(cfg$code_output_dir)
ctx <- fetch_issue_tracking(skill_dir = skill, entity_label = entity_label, group_label = group_label)
merged <- read_named_tracking_file(ctx, merged_filename, entity_label = entity_label, group_label = group_label)
if (is.null(merged)) stop("No such merged file found: ", merged_filename)

commit_issue_tracking(merged, skill_dir = skill, fetch_ctx = ctx, entity_label = entity_label, group_label = group_label)
delete_named_tracking_file(ctx, merged_filename)

message("Committed ", merged_filename, " -> issue_tracking.xlsx (", nrow(merged), " rows). ", merged_filename, " deleted.")

# Checks that merging findings into the tracking file didn't silently drop
# or duplicate anything, run automatically before the merged file is written.

#' Compares the tracking file before/after a merge against the fresh check
#' output. `dropped`: a finding present before or in the fresh run but
#' missing after merging — always a bug. `unexpected_added`: a finding in
#' the result that shouldn't be there — always a bug. `content_diffs`:
#' Issue/Value text that changed for an already-tracked finding — kept
#' as-is by design, flagged here only as a note worth a human glance.
verify_findings_merge <- function(current, snapshot, merged) {
    cur_ids <- as.character(current$finding_id)
    snap_ids <- as.character(snapshot$finding_id)
    merged_ids <- as.character(merged$finding_id)

    dropped <- union(setdiff(cur_ids, merged_ids), setdiff(snap_ids, merged_ids))
    unexpected_added <- setdiff(merged_ids, union(cur_ids, snap_ids))

    both_ids <- intersect(cur_ids, snap_ids)
    content_diffs <- character()
    diff_cols <- intersect(c("issue", "value"), intersect(names(current), names(snapshot)))
    if (length(both_ids) && length(diff_cols)) {
        cur_m <- current[match(both_ids, cur_ids), , drop = FALSE]
        snap_m <- snapshot[match(both_ids, snap_ids), , drop = FALSE]
        for (col in diff_cols) {
        changed <- as.character(cur_m[[col]]) != as.character(snap_m[[col]])
        changed[is.na(changed)] <- FALSE
        if (any(changed)) {
            content_diffs <- c(content_diffs, sprintf("%s: %s text changed", both_ids[changed], col))
        }
        }
    }

    list(
        ok = length(dropped) == 0 && length(unexpected_added) == 0,
        dropped = dropped, unexpected_added = unexpected_added, content_diffs = content_diffs,
        n_current = nrow(current), n_snapshot = nrow(snapshot), n_merged = nrow(merged)
    )
}

#' Same check for a resolutions merge (Status/Corrections updates from the
#' field team). `dropped`: a finding that disappeared — should never
#' happen. `unexpected_new_ids`: a finding in the clone that wasn't already
#' tracked — suspicious.
verify_resolution_merge <- function(current, clone, merged) {
    cur_ids <- as.character(current$finding_id)
    clone_ids <- as.character(clone$finding_id)
    merged_ids <- as.character(merged$finding_id)

    dropped <- setdiff(cur_ids, merged_ids)
    unexpected_new_ids <- setdiff(clone_ids, cur_ids)

    list(
        ok = length(dropped) == 0 && length(unexpected_new_ids) == 0,
        dropped = dropped, unexpected_new_ids = unexpected_new_ids,
        n_current = nrow(current), n_clone = nrow(clone), n_merged = nrow(merged)
    )
}

#' Human-readable summary for either verification result above.
format_merge_verification <- function(v) {
    has_content_diffs <- length(v$content_diffs %||% character()) > 0
    if (isTRUE(v$ok) && !has_content_diffs) {
        return(sprintf("Merge verification: OK (%s -> %s rows).", v$n_current %||% NA, v$n_merged %||% NA))
    }
    lines <- character()
    if (length(v$dropped %||% character())) {
        lines <- c(lines, paste0("DROPPED (would silently disappear from tracking): ", paste(v$dropped, collapse = ", ")))
    }
    if (length(v$unexpected_added %||% character())) {
        lines <- c(lines, paste0("UNEXPECTED new id(s) in the merge result: ", paste(v$unexpected_added, collapse = ", ")))
    }
    if (length(v$unexpected_new_ids %||% character())) {
        lines <- c(lines, paste0("UNEXPECTED id(s) in the clone not already tracked: ", paste(v$unexpected_new_ids, collapse = ", ")))
    }
    if (has_content_diffs) {
        lines <- c(lines, paste0("Content changed but kept as-is (review note): ", paste(v$content_diffs, collapse = "; ")))
    }
    header <- if (isTRUE(v$ok)) "Merge verification: passed, with review notes" else "Merge verification: BLOCKED"
    paste0(header, "\n  ", paste(lines, collapse = "\n  "))
}

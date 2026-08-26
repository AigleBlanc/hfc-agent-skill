# SurveyCTO media helpers + M13 checks (audio / pictures).
# Filename columns hold paths like "media\uuid.m4a" (a literal Windows-style
# backslash, not an escape sequence); binaries live under media_folder.

is_empty_media_cell <- function(x) {
  is.na(x) | !nzchar(trimws(as.character(x)))
}

#' M13: flags a media-indicating column that's completely empty across
#' every surveyed row — a likely form/coding problem, not a per-row check.
run_m13_media_checks <- function(ds, roles, modules) {
  suppressPackageStartupMessages({ library(dplyr); library(tibble) })
  if (!isTRUE(modules$M13$on)) return(empty_findings())

  audio_cols <- modules$M13$audio_cols %||% roles$audio_file_cols %||% character()
  image_cols <- modules$M13$image_cols %||% roles$image_file_cols %||% character()
  other_cols <- modules$M13$other_cols %||% roles$qualitative_text_cols %||% character()
  audio_cols <- intersect(as.character(audio_cols), names(ds))
  image_cols <- intersect(as.character(image_cols), names(ds))
  other_cols <- intersect(as.character(other_cols), names(ds))
  all_cols <- unique(c(audio_cols, image_cols, other_cols))
  if (!length(all_cols)) return(empty_findings())

  out <- list()
  for (col in all_cols) {
    kind <- if (col %in% audio_cols) "audio" else if (col %in% image_cols) "image" else "qualitative"
    vals <- as.character(ds[[col]])
    if (nrow(ds) > 0 && all(is_empty_media_cell(vals))) {
      out[[col]] <- tibble(
        finding_id = paste0("m13:column_empty:", col),
        check_id = sprintf("media_column_empty_%s", col),
        check_module = "M13",
        category = "media_column_empty",
        issue = sprintf(
          "The %s column '%s' is empty across all %d surveyed rows. Likely a form/coding problem (the field isn't showing up in the app, or the question is misconfigured), not a data-entry gap on any one row",
          kind, var_label(col, roles), nrow(ds)
        ),
        submission_id = "", group_id = "", enumerator = "", start_date = "", end_date = "",
        key = "", value = "", variable = col, entity_name = "", group_name = "", enumerator_name = "",
        sort_value = NA_real_
      )
    }
  }

  findings <- dplyr::bind_rows(out)
  if (is.null(findings) || nrow(findings) == 0) return(empty_findings())
  findings
}

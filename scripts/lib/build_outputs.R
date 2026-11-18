# Builds the issue-tracking workbook, HTML report, and project scaffold.

# The issue-tracking column order and headers, in one place — entity_label/
# group_label swap in your configured labels (e.g. "Farmer ID"/"School")
# instead of the generic "Entity ID"/"Group".
issue_tracking_header_map <- function(entity_label = NA_character_, group_label = NA_character_) {
    eid <- if (!is.na(entity_label) && nzchar(entity_label)) entity_label else "Entity ID"
    grp <- if (!is.na(group_label) && nzchar(group_label)) group_label else "Group"
    c(
        startdate             = "Startdate",
        enddate               = "Enddate",
        today_date            = "Today's Date",
        entity_id             = eid,
        group                 = grp,
        enumerator            = "Enumerator",
        issue                 = "Issue",
        value                 = "Value",
        comment               = "Comment",
        corrections           = "Corrections",
        correction_author     = "Correction Author",
        status                = "Status",
        issue_category        = "Issue Category",
        variable              = "Variable (DIME use)",
        unique_submission_id  = "Unique Submission ID",
        finding_id            = "Issue ID"
    )
}

# Rename internal snake_case columns to their display header labels, for
# writing to disk in the shared sync folder. Columns not in the map pass
# through unchanged.
rename_to_issue_tracking_headers <- function(tbl, entity_label = NA_character_, group_label = NA_character_) {
    tbl <- as.data.frame(tbl, stringsAsFactors = FALSE)
    hmap <- issue_tracking_header_map(entity_label, group_label)
    present <- intersect(names(hmap), names(tbl))
    names(tbl)[match(present, names(tbl))] <- hmap[present]
    tbl
}

# Inverse of rename_to_issue_tracking_headers() — for reading from disk
# back into internal snake_case names.
rename_from_issue_tracking_headers <- function(tbl, entity_label = NA_character_, group_label = NA_character_) {
    tbl <- as.data.frame(tbl, stringsAsFactors = FALSE)
    hmap <- issue_tracking_header_map(entity_label, group_label)
    inv <- setNames(names(hmap), hmap)
    present <- intersect(names(inv), names(tbl))
    names(tbl)[match(present, names(tbl))] <- inv[present]
    tbl
}

# Converts findings to the issue-tracking shape, ready to write.
findings_to_issue_tracking <- function(findings, roles = NULL) {
    suppressPackageStartupMessages({ library(dplyr); library(tibble) })
    cols <- names(issue_tracking_header_map())
    if (nrow(findings) == 0) {
        return(as_tibble(setNames(rep(list(character()), length(cols)), cols)))
    }
    entity_mode <- roles$entity_display %||% "id"
    group_mode <- roles$group_display %||% "name"
    enum_mode <- roles$enumerator_display %||% "name"
    findings %>%
        transmute(
            startdate = start_date,
            enddate = end_date,
            today_date = format(Sys.time(), "%Y%m%d%H%M"),
            entity_id = resolve_display_vec(submission_id, entity_name, entity_mode),
            group = resolve_display_vec(group_id, group_name, group_mode),
            enumerator = resolve_display_vec(enumerator, enumerator_name, enum_mode),
            issue,
            value,
            comment = "",
            corrections = "",
            correction_author = "",
            status = "Open",
            issue_category = category_label(category),
            variable,
            unique_submission_id = key,
            finding_id
        )
}

# The single shared Status normalizer (internal snake_case `status` column).
# Migrates the old status(Open/accepted/revise)+resolved(No/yes/partial)
# pair into the current 5-value vocabulary (Open/Accepted/Revise/Resolved/
# Needs Review), then canonicalizes casing for known values. Unrecognized
# non-blank Status values pass through unchanged.
normalize_issue_tracking_status <- function(tbl) {
    suppressPackageStartupMessages({ library(dplyr) })
    tbl <- as.data.frame(tbl, stringsAsFactors = FALSE)
    n <- nrow(tbl)
    if (!"status" %in% names(tbl) && "ra_status" %in% names(tbl)) {
        tbl$status <- tbl$ra_status
    }
    if (!"status" %in% names(tbl)) tbl$status <- rep("Open", n)
    tbl$status[is.na(tbl$status) | !nzchar(as.character(tbl$status))] <- "Open"

    if ("resolved" %in% names(tbl)) {
        st <- tolower(as.character(tbl$status))
        rs <- tolower(as.character(tbl$resolved))
        rs[is.na(rs) | !nzchar(rs)] <- "no"
        tbl$status <- dplyr::case_when(
        st == "accepted" & rs == "yes" ~ "Resolved",
        st == "accepted" & rs == "partial" ~ "Needs Review",
        st == "accepted" ~ "Accepted",
        st == "revise" ~ "Revise",
        TRUE ~ "Open"
        )
        tbl$resolved <- NULL
    } else {
        known <- c("Open", "Accepted", "Revise", "Resolved", "Needs Review")
        hit <- match(tolower(as.character(tbl$status)), tolower(known))
        tbl$status[!is.na(hit)] <- known[hit[!is.na(hit)]]
    }
    tbl$ra_status <- NULL
    tbl$check_module <- NULL
    tbl
}

# Normalize Status, fill/reorder to the canonical column set, and rename to
# display header labels — the one shared prep step every writer (local xlsx,
# local csv) must apply identically so the live file stays consistent.
prepare_tracking_display <- function(tbl, entity_label = NA_character_, group_label = NA_character_) {
    tbl <- normalize_issue_tracking_status(tbl)
    cols <- names(issue_tracking_header_map())
    for (c in cols) if (!c %in% names(tbl)) tbl[[c]] <- ""
    tbl <- tbl[, cols, drop = FALSE]
    rename_to_issue_tracking_headers(tbl, entity_label, group_label)
}

# Write the issue-tracking csv + xlsx (Tracking/Findings/Instructions tabs).
write_issue_tracking <- function(tbl, findings, xlsx_path, csv_path, entity_label = NA_character_, group_label = NA_character_) {
    suppressPackageStartupMessages({ library(openxlsx); library(readr) })
    display <- prepare_tracking_display(tbl, entity_label, group_label)

    dir.create(dirname(csv_path), recursive = TRUE, showWarnings = FALSE)
    dir.create(dirname(xlsx_path), recursive = TRUE, showWarnings = FALSE)
    write_csv(display, csv_path)

    wb <- createWorkbook()
    addWorksheet(wb, "Tracking")
    writeData(wb, "Tracking", display)
    if (!is.null(findings) && nrow(findings) > 0) {
        addWorksheet(wb, "Findings")
        writeData(wb, "Findings", findings)
    }
    addWorksheet(wb, "Instructions")
    writeData(wb, "Instructions", data.frame(
        step = 1:4,
        action = c(
        "Field: fill Comment and Corrections",
        "RA: set Status to Accepted | Revise | leave Open",
        "RA: set Correction Author",
        "When ready in chat: Process HFC feedback"
        )
    ))
    saveWorkbook(wb, xlsx_path, overwrite = TRUE)
}

# Reads a raw xlsx sheet with header cells taken verbatim (no space-to-dot
# mangling).
read_xlsx_verbatim_headers <- function(path, sheet) {
    raw <- openxlsx::readWorkbook(path, sheet = sheet, colNames = FALSE)
    if (nrow(raw) < 1) return(as.data.frame(raw, stringsAsFactors = FALSE))
    hdr <- as.character(unlist(raw[1, ]))
    body <- raw[-1, , drop = FALSE]
    names(body) <- hdr
    as.data.frame(body, stringsAsFactors = FALSE, check.names = FALSE)
    }

# Normalizes blank cells to "" regardless of whether they came in as NA.
blank_na_to_empty <- function(tbl) {
    as.data.frame(lapply(tbl, function(col) {
        if (!is.character(col)) col <- as.character(col)
        col[is.na(col)] <- ""
        col
    }), stringsAsFactors = FALSE, check.names = FALSE)
}

# Reads the issue-tracking csv/xlsx back in, erroring loudly if the header
# row was corrupted by an edit made outside this skill's own write path.
read_issue_tracking <- function(path, sheet = "Tracking", entity_label = NA_character_, group_label = NA_character_) {
    suppressPackageStartupMessages({ library(readr); library(openxlsx) })
    ext <- tolower(tools::file_ext(path))
    raw <- if (ext == "csv") {
        as.data.frame(read_csv(path, show_col_types = FALSE), stringsAsFactors = FALSE)
    } else {
        read_xlsx_verbatim_headers(path, sheet)
    }
    renamed <- rename_from_issue_tracking_headers(raw, entity_label, group_label)
    if (!"finding_id" %in% names(renamed)) {
        stop(
        "read_issue_tracking(): '", path, "' has no recognizable 'Issue ID' column after header mapping ",
        "(found: ", paste(names(raw), collapse = ", "), "). The header row may have been overwritten by a ",
        "raw edit outside this skill's own write functions (read_named_tracking_file()/write_named_tracking_file()) ",
        "— restore the file from a backup/snapshot rather than proceeding."
        )
    }
    normalize_issue_tracking_status(blank_na_to_empty(renamed))
}

# Merges a fresh snapshot into the live tracking file, preserving existing
# rows exactly as they are (never refreshed) and appending genuinely new
# findings. `current` may be NULL on a first-ever run.
merge_preserve_existing <- function(current, new_snapshot) {
    if (is.null(current) || !nrow(current)) return(new_snapshot)
    new_only <- new_snapshot[!new_snapshot$finding_id %in% current$finding_id, , drop = FALSE]
    dplyr::bind_rows(current, new_only)
}

# Merges Status/Corrections edits back into the live tracking file — a row
# only gets the clone's edits if it's in `touched_ids`, so a concurrent
# field/RA edit to an untouched row is never clobbered by a stale clone.
merge_resolution_updates <- function(current, resolution_clone, touched_ids = NULL) {
    if (is.null(current) || !nrow(current)) return(resolution_clone)
    update_cols <- c("status", "corrections", "correction_author")
    idx <- match(current$finding_id, resolution_clone$finding_id)
    matched <- !is.na(idx)
    if (!is.null(touched_ids)) {
        matched <- matched & as.character(current$finding_id) %in% touched_ids
    }
    merged <- current
    for (col in update_cols) {
        if (col %in% names(resolution_clone)) {
        merged[[col]][matched] <- resolution_clone[[col]][idx[matched]]
        }
    }
    clone_only <- resolution_clone[!resolution_clone$finding_id %in% current$finding_id, , drop = FALSE]
    dplyr::bind_rows(merged, clone_only)
}

# Display-only filter: drops any finding marked Resolved (or no longer
# tracked) from what the report shows. The tracking file itself is untouched.
filter_findings_by_tracking_status <- function(findings, tracking_tbl) {
    if (is.null(findings) || nrow(findings) == 0) return(findings)
    if (is.null(tracking_tbl) || nrow(tracking_tbl) == 0 || !"finding_id" %in% names(tracking_tbl)) {
        return(findings[0, , drop = FALSE])
    }
    status <- toupper(trimws(as.character(tracking_tbl$status %||% "")))
    keep_ids <- tracking_tbl$finding_id[status != "RESOLVED"]
    findings[findings$finding_id %in% keep_ids, , drop = FALSE]
}

MODULE_ORDER <- paste0("M", 1:14)

# content_type: "findings" (default) | "stats" (descriptive only) |
# "custom_html" (supplies its own body).
MODULE_META <- list(
    M1 = list(label = "Completion",
                desc = "Reports submitted and completed surveys overall, and by group, enumerator, and date, so gaps in fieldwork show up early."),
    M2 = list(label = "Duplicates",
                desc = "Flags submissions that share the same unique ID or survey key, one row per duplicate group rather than one row per individual duplicate submission."),
    M3 = list(label = "Form Version",
                desc = "Tracks which version of the survey instrument was in use on each date, and flags any submission whose recorded version doesn't match the expected window for its date."),
    M4 = list(label = "Survey Duration",
                desc = "Reports how long interviews took, in minutes, overall, by section, and by enumerator, and flags individual interviews (or sections) that ran unusually long or short."),
    M5 = list(label = "Irregular Timing",
                desc = "Flags interviews conducted at unusual times: weekends (if configured) or outside normal working hours, using each submission's local time zone."),
    M6 = list(label = "Numeric Outliers",
                desc = "Flags unusually high or low values on key numeric questions against fixed, literature/analyst-supplied thresholds."),
    M7 = list(label = "Missingness",
                desc = "A reference table of missingness on key survey questions — descriptive only, never produces findings, on either the question or the enumerator level.",
                content_type = "stats"),
    M8 = list(label = "Straightlining",
                desc = "Flags enumerators who gave the same answer on a question in 100%+ of their interviews on a single day (minimum 3 that day), and submissions where 90%+ of ordinal/Likert-style answers are identical.",
                findings_title = "By enumerator"),
    M9 = list(label = "Field Request",
                desc = "The field team and user's own daily reconciliation view — a custom, survey-specific check whose rows are a status snapshot, not a problem to fix. Any finding that isn't a Field Request reconciliation item renders in 'Other' instead.",
                issue_col_label = "Info", no_issues_word = "No entries.", count_noun = "entries"),
    M10 = list(label = "GPS Map",
                desc = "An interactive map plotting every submission's GPS location, for visual review — descriptive only, this section never flags an issue by default.",
                content_type = "custom_html"),
    M11 = list(label = "Summary Statistics",
                desc = "A simple reference table of mean, SD, min, max, and observation count for the survey's most important variables, overall and broken out per enumerator.",
                content_type = "stats"),
    M12 = list(label = "Balance Tables",
                desc = "Standard RCT balance check: compares baseline covariates across treatment arms and other configured splits, alongside a completed-vs-submitted reconciliation and a differential-completion regression. Descriptive only, never produces findings.",
                content_type = "custom_html"),
    M13 = list(label = "Media Files",
                desc = "Flags a media-indicating column (audio, image, or qualitative-capture) that is completely empty across every surveyed row — a single finding per affected column, not per row."),
    M14 = list(label = "Consent & Assent",
                desc = "Flags cases missing a required consent (guardian agreement) or assent (the child's own agreement) flag, which the survey should always capture before proceeding.")
)

#' Which modules get their own report section, in final display order.
#' A module appears if it produced row-level findings OR non-empty
#' descriptive stats (stats-only modules like Missingness/Summary
#' Statistics never produce findings rows at all; M1/M3/M4/M7 can have
#' stats with zero findings) OR is simply configured `on` (an on-and-clean
#' check still gets a section, showing its no-issues placeholder, rather
#' than being silently omitted — different from a check that never ran at
#' all, which stays fully absent). Factored out of write_html_report()'s
#' render loop so scripts/lib/report_contract.R's validator can compute the
#' exact same set independently and the two can never structurally drift
#' apart.
compute_modules_present <- function(findings, stats, modules) {
    present_from_findings <- if (!is.null(findings) && nrow(findings) && "check_module" %in% names(findings)) {
        unique(findings$check_module)
    } else character()
    stats_nonempty <- function(s) {
        if (is.null(s)) return(FALSE)
        if (is.data.frame(s)) return(nrow(s) > 0)
        if (is.list(s)) return(any(vapply(s, function(x) is.data.frame(x) && nrow(x) > 0, logical(1))))
        FALSE
    }
    present_from_stats <- if (!is.null(stats)) names(stats)[vapply(stats, stats_nonempty, logical(1))] else character()
    present_from_on <- if (!is.null(modules)) {
        names(modules)[vapply(names(modules), function(m) isTRUE(modules[[m]]$on), logical(1))]
    } else character()
    modules_present <- intersect(MODULE_ORDER, Reduce(union, list(present_from_findings, present_from_stats, present_from_on)))
    # Descriptive reference sections (Summary Statistics, Balance Tables)
    # render last, right before All Issues.
    PINNED_TO_END <- c("M11", "M12")
    c(setdiff(modules_present, PINNED_TO_END), intersect(PINNED_TO_END, modules_present))
}

module_label <- function(code) {
    code <- as.character(code)
    vapply(code, function(x) {
        m <- MODULE_META[[x]]
        if (is.null(m)) x else m$label
    }, character(1), USE.NAMES = FALSE)
}

# Uses the project's actual configured thresholds when available, else the
# generic static description.
module_desc <- function(code, modules = NULL) {
    code <- as.character(code)
    m <- MODULE_META[[code]]
    static_desc <- if (is.null(m)) "" else m$desc
    if (is.null(modules)) return(static_desc)
    builder <- DYNAMIC_MODULE_DESC[[code]]
    if (is.null(builder)) return(static_desc)
    dyn <- tryCatch(builder(modules), error = function(e) NA_character_)
    if (is.na(dyn) || !nzchar(dyn)) static_desc else dyn
}

# Human-readable labels for findings$category values.
CATEGORY_LABELS <- list(
    low_completion_enum_day = "Below daily target",
    replacement_sequence_gap = "Replacement sequence gap",
    duplicates = "Duplicate submission",
    form_version_mismatch = "Form version mismatch",
    long_duration = "Interview too long",
    short_duration = "Interview too short",
    irregular_time = "Irregular interview time",
    age_outlier = "Age outlier",
    numeric_outlier = "Numeric outlier",
    high_missingness = "High missingness",
    gps_distance = "GPS distance outlier",
    straightlining_enum = "Straightlining (by enumerator)",
    straightlining_survey = "Straightlining (within submission)",
    media_column_empty = "Media column empty (all rows)",
    assent = "Missing assent",
    consent = "Missing consent",
    audio = "Missing audio consent flag",
    assent_column_empty = "Assent column empty (all rows)",
    consent_column_empty = "Consent column empty (all rows)",
    audio_column_empty = "Audio consent column empty (all rows)"
)

category_label <- function(category) {
    category <- as.character(category)
    vapply(category, function(x) {
        lbl <- CATEGORY_LABELS[[x]]
        if (!is.null(lbl)) return(lbl)
        words <- strsplit(gsub("_", " ", x), " ")[[1]]
        words <- ifelse(nzchar(words), paste0(toupper(substr(words, 1, 1)), substr(words, 2, nchar(words))), words)
        paste(words, collapse = " ")
    }, character(1), USE.NAMES = FALSE)
}

FINDING_SORT_DIRECTION <- c(
    long_duration = "desc", short_duration = "asc",
    irregular_time = "desc",
    age_outlier = "desc", numeric_outlier = "desc",
    high_missingness = "desc",
    gps_distance = "desc",
    straightlining_enum = "desc", straightlining_survey = "desc"
)

# Orders findings by module, then within a module: date descending
# (dateless findings sort last), then enumerator, then submission ID.
sort_findings_for_display <- function(df) {
    if (is.null(df) || nrow(df) == 0) return(df)
    module_rank <- match(df$check_module, MODULE_ORDER)
    module_rank[is.na(module_rank)] <- length(MODULE_ORDER) + 1L
    enum <- if ("enumerator" %in% names(df)) as.character(df$enumerator) else rep("", nrow(df))
    sid  <- if ("submission_id" %in% names(df)) as.character(df$submission_id) else rep("", nrow(df))
    enum[is.na(enum)] <- ""
    sid[is.na(sid)] <- ""
    date_key <- suppressWarnings(as.numeric(as.Date(finding_date_vec(df))))
    date_key[is.na(date_key)] <- -Inf
    ord <- order(module_rank, -date_key, enum == "", enum, sid == "", sid)
    df[ord, , drop = FALSE]
}

# Searchable HTML table: all rows in DOM; first `show_n` visible until search.
# Tables with fewer than TRUNCATE_THRESHOLD rows always render in full (no
# toggle). Larger tables default to `show_n` rows + a "Show all" button that
# toggles to "Show top 15" (collapsing back to a 15-row view, not `show_n`).
TRUNCATE_THRESHOLD <- 15L

html_searchable_table <- function(df, cols, table_id, show_n = 10L, col_labels = NULL) {
    esc <- function(x) {
        x <- as.character(x)
        x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE)
        x <- gsub("<", "&lt;", x, fixed = TRUE)
        x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    if (is.null(df) || nrow(df) == 0) {
        return(paste0(
        "<div class='table-wrap' id='", table_id, "-wrap'>",
        "<p class='meta'>No rows</p></div>"
        ))
    }
    cols <- intersect(cols, names(df))
    if (!length(cols)) cols <- names(df)
    truncate <- nrow(df) >= TRUNCATE_THRESHOLD
    initial_shown <- if (truncate) min(show_n, nrow(df)) else nrow(df)
    labels <- if (!is.null(col_labels)) {
        # `[[` on a named CHARACTER VECTOR (unlike a list) errors on a
        # missing name instead of returning NULL — check membership first
        # so an unmapped column (e.g. a stats table with its own already-
        # human-readable column names) falls back to itself instead of
        # crashing the whole render.
        vapply(cols, function(cn) if (cn %in% names(col_labels)) col_labels[[cn]] else cn, character(1))
    } else cols
    head_cells <- paste0("<th>", esc(labels), "</th>", collapse = "")
    rows <- vapply(seq_len(nrow(df)), function(i) {
        cls_parts <- c(if (truncate && i > show_n) "row-hidden")
        cls <- if (length(cls_parts)) paste0(" class='", paste(cls_parts, collapse = " "), "'") else ""
        cells <- paste0(
        vapply(cols, function(cn) paste0("<td>", esc(df[[cn]][i]), "</td>"), character(1)),
        collapse = ""
        )
        paste0("<tr", cls, ">", cells, "</tr>")
    }, character(1))
    toggle_html <- if (truncate) {
        paste0(
        "<button type='button' class='table-toggle' data-table='", table_id,
        "' data-expanded='false'>Show all</button>"
        )
    } else ""
    paste0(
        "<div class='table-wrap' data-collapsed-n='", show_n, "' id='", table_id, "-wrap'>",
        "<div class='table-toolbar'>",
        "<input type='search' class='table-search' placeholder='Search all ", nrow(df),
        " rows…' aria-label='Search table' data-table='", table_id, "' />",
        toggle_html,
        "<span class='table-count' data-for='", table_id, "'>",
        initial_shown, " of ", nrow(df), " shown</span></div>",
        "<table class='searchable' id='", table_id, "'><thead><tr>", head_cells,
        "</tr></thead><tbody>", paste(rows, collapse = "\n"),
        "</tbody></table></div>"
    )
}

# Formats any `pct_*` column as a 1-decimal percentage string (87.3 -> "87.3%").
format_pct_cols <- function(df) {
    pct_cols <- grep("^pct_", names(df), value = TRUE)
    for (cn in pct_cols) {
        df[[cn]] <- paste0(round1(suppressWarnings(as.numeric(df[[cn]]))), "%")
    }
    df
}

# Column header labels for render_stats_block()'s tables, keyed by module
# (the same column name means different things in different modules).
STATS_COL_LABELS <- list(
    # Fixed Completion structure: Submitted, Submitted (Primary Sample) (only
    # when a primary sample is known), Completed, Completion (= Completed /
    # Submitted (Primary Sample), or / Submitted without a primary sample).
    M1 = c(n = "Submitted", n_primary = "Submitted (Primary Sample)", n_complete = "Completed",
            pct_complete = "Completion",
            group = "Group", group_var = "Variable", value = "Value",
            enumerator = "Enumerator", date = "Date", reason = "Reason", count = "Count",
            dates = "Dates"),
    M3 = c(version = "Version", n = "N", date_min = "First seen", date_max = "Last seen",
            date_start = "Window start", date_end = "Window end", expected_dates = "Expected Dates"),
    M4 = c(dates = "Dates", date = "Date", level = "Section", n = "N", mean = "Mean", median = "Median", sd = "SD",
            min = "Min", max = "Max", enumerator = "Enumerator"),
    M7 = c(variable = "Variable", pct_missing = "% Missing", n_missing = "N Missing", n = "Obs"),
    M11 = c(Variable = "Variable", `Overall Mean` = "Overall Mean", Median = "Median",
            Mean = "Mean", SD = "SD", Min = "Min", Max = "Max", Missing = "NA", Obs = "Obs")
)

# Table titles auto-derive from their list name (snake_case -> Title Case)
# — these are the exceptions where that guess doesn't match the real name.
STATS_TABLE_TITLE_OVERRIDES <- list(
    by_reason = "Non-completion reasons",
    by_day_times = "Day times",
    by_variable = "Overall"
)

STATS_BLOCK_COLLAPSE_AFTER <- 4L

# Renders one table per named element of `mod_stats`. Above
# STATS_BLOCK_COLLAPSE_AFTER entries, every table after the first collapses
# into a <details> with a jump index at the top.
render_stats_block <- function(mod_stats, prefix, col_labels = NULL) {
    if (is.null(mod_stats)) return("")
    esc <- function(x) {
        x <- as.character(x)
        x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE)
        x <- gsub("<", "&lt;", x, fixed = TRUE)
        x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    if (is.data.frame(mod_stats)) mod_stats <- list(Summary = mod_stats)
    present <- names(mod_stats)[vapply(mod_stats, function(df) is.data.frame(df) && nrow(df) > 0, logical(1))]
    collapse <- length(present) > STATS_BLOCK_COLLAPSE_AFTER

    index_links <- character()
    blocks <- character()
    for (nm in present) {
        df <- format_pct_cols(mod_stats[[nm]])
        tid <- paste0("tbl-", prefix, "-", tolower(gsub("[^A-Za-z0-9]+", "-", nm)))
        label <- if (nm %in% names(STATS_TABLE_TITLE_OVERRIDES)) {
        STATS_TABLE_TITLE_OVERRIDES[[nm]]
        } else {
        l <- gsub("_", " ", nm)
        paste0(toupper(substr(l, 1, 1)), substr(l, 2, nchar(l)))
        }
        table_html <- html_searchable_table(df, names(df), tid, 10L, col_labels = col_labels)
        is_first <- identical(nm, present[[1]])
        if (collapse && !is_first) {
        # NOTE: html_searchable_table() already puts id="{tid}" on the
        # <table> itself (and "{tid}-wrap" on its wrapper div) — the details
        # anchor must use a third, distinct suffix to avoid a duplicate id.
        index_links <- c(index_links, sprintf("<a href='#%s-details'>%s</a>", tid, esc(label)))
        blocks <- c(blocks, sprintf(
            "<details class='stats-details' id='%s-details'><summary>%s</summary>%s</details>",
            tid, esc(label), table_html
        ))
        } else {
        blocks <- c(blocks, paste0("<h4>", esc(label), "</h4>", table_html))
        }
    }
    idx_html <- if (length(index_links)) {
        paste0("<nav class='stats-index'>", paste(index_links, collapse = " &middot; "), "</nav>")
    } else ""
    paste0(idx_html, paste(blocks, collapse = ""))
}

# Per-CATEGORY (not per-module) display columns for the HTML report's
# findings tables — a category's granularity (an aggregate unit like an
# enumerator/site, vs. one individual submission) determines what's
# meaningful to show, independent of which module produced it. This is what
# keeps a table from carrying columns the underlying check never actually
# established (e.g. no Entity/Group column on a by-enumerator missingness
# table — mk_aggregate_finding() never populated those fields in the first
# place, see utils.R). `entity_display`/`group_display`/`enumerator_display`
# are computed once below via resolve_display_vec() (utils.R) — entity_display
# is the raw ID by default (roles$entity_display, default "id" — we never
# have the respondent's real name), group/enumerator_display resolve to
# name-if-available by default (roles$group_display/enumerator_display,
# default "name").
FINDINGS_COLS_AGGREGATE_GROUP       <- c("group_display", "issue")
FINDINGS_COLS_AGGREGATE_ENUM        <- c("enumerator_display", "issue")
FINDINGS_COLS_AGGREGATE_ENUM_VALUE  <- c("enumerator_display", "issue", "value")
FINDINGS_COLS_AGGREGATE_ENUM_DATE_VALUE <- c("date_display", "enumerator_display", "issue", "value")
FINDINGS_COLS_AGGREGATE_SURVEY      <- c("issue")
FINDINGS_COLS_AGGREGATE_ENTITY_VALUE <- c("entity_display", "issue", "value")
FINDINGS_COLS_ROW_BASE         <- c("date_display", "entity_display", "group_display", "enumerator_display", "issue")
FINDINGS_COLS_ROW_VALUE        <- c("date_display", "entity_display", "group_display", "enumerator_display", "issue", "value")
FINDINGS_COLS_ROW_VALUE_VAR    <- c("date_display", "entity_display", "group_display", "enumerator_display", "issue", "value", "variable_display")
# Form Version's ISSUES table has no Group column.
FINDINGS_COLS_ROW_VALUE_NO_GROUP <- c("date_display", "entity_display", "enumerator_display", "issue", "value")
# Survey Duration's ISSUES table shows the Treatment/Control arm instead of
# the general Group column.
FINDINGS_COLS_ROW_VALUE_ARM    <- c("date_display", "entity_display", "arm_display", "enumerator_display", "issue", "value")

CATEGORY_COLS <- list(
    replacement_sequence_gap = FINDINGS_COLS_ROW_VALUE,
    low_completion_enum_day = FINDINGS_COLS_ROW_VALUE,
    duplicates             = FINDINGS_COLS_AGGREGATE_ENTITY_VALUE,
    form_version_mismatch  = FINDINGS_COLS_ROW_VALUE_NO_GROUP,
    long_duration          = FINDINGS_COLS_ROW_VALUE_ARM,
    short_duration          = FINDINGS_COLS_ROW_VALUE_ARM,
    irregular_time         = FINDINGS_COLS_ROW_VALUE,
    age_outlier            = FINDINGS_COLS_ROW_VALUE_VAR,
    numeric_outlier        = FINDINGS_COLS_ROW_VALUE_VAR,
    high_missingness       = FINDINGS_COLS_AGGREGATE_ENUM_VALUE,
    gps_distance           = FINDINGS_COLS_ROW_BASE,
    straightlining_enum    = FINDINGS_COLS_AGGREGATE_ENUM_DATE_VALUE,
    straightlining_survey  = FINDINGS_COLS_ROW_VALUE,
    media_column_empty     = FINDINGS_COLS_AGGREGATE_SURVEY,
    assent                 = FINDINGS_COLS_ROW_BASE,
    consent                = FINDINGS_COLS_ROW_BASE,
    audio                  = FINDINGS_COLS_ROW_BASE,
    assent_column_empty    = FINDINGS_COLS_AGGREGATE_SURVEY,
    consent_column_empty   = FINDINGS_COLS_AGGREGATE_SURVEY,
    audio_column_empty     = FINDINGS_COLS_AGGREGATE_SURVEY
)
# Unmatched categories (e.g. an M9 custom check's own category) land in
# "Other", whose ISSUES table is the full row-level set including Variable.
DEFAULT_FINDINGS_COLS <- FINDINGS_COLS_ROW_VALUE_VAR

# Last Day / All Issues stay ONE combined table each, using the superset
# column set — a row that doesn't have a given column (e.g. an aggregate
# finding with no Entity) just shows blank there.
ALL_FINDINGS_COLS <- c("date_display", "entity_display", "group_display", "enumerator_display", "issue", "value", "variable_display")

#' All Issues' per-enumerator breakdown — the one place a findings table
#' splits by enumerator, worst (most issues) first. Findings with no
#' enumerator go into a trailing "Unassigned" panel.
render_all_issues_by_enumerator <- function(findings, col_labels) {
    if (is.null(findings) || nrow(findings) == 0 || !"enumerator_display" %in% names(findings)) return("")
    esc <- function(x) {
        x <- as.character(x); x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE); x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    enum <- as.character(findings$enumerator_display)
    enum[!nzchar(enum) %in% TRUE] <- NA_character_
    if (!any(!is.na(enum))) return("")
    counts <- sort(table(enum[!is.na(enum)]), decreasing = TRUE)
    ordered <- names(counts)
    if (any(is.na(enum))) ordered <- c(ordered, NA_character_)
    blocks <- character()
    for (i in seq_along(ordered)) {
        u <- ordered[[i]]
        idx <- if (is.na(u)) which(is.na(enum)) else which(enum == u)
        grp_df <- findings[idx, , drop = FALSE]
        label <- if (is.na(u)) "Unassigned" else u
        tid <- paste0("tbl-all-enum-", i)
        table_html <- html_searchable_table(grp_df, ALL_FINDINGS_COLS, tid, 10L, col_labels = col_labels)
        blocks <- c(blocks, sprintf(
            "<details class='enum-issues'><summary>%s <span class='meta'>(%d issue%s)</span></summary>%s</details>",
            esc(label), length(idx), if (length(idx) == 1) "" else "s", table_html
        ))
    }
    paste(blocks, collapse = "")
}

#' Enumerator ranking table: Enumerator | Number of days | Completed
#' surveys | Number of issues | Rate, sorted by Rate descending. Sits
#' between the flat ALL ISSUES table and the per-enumerator panels below.
render_all_issues_enumerator_table <- function(findings, stats, ds, roles, table_id = "tbl-all-enumerators") {
    by_enum_completion <- stats$M1$by_enumerator
    if (is.null(by_enum_completion) || !is.data.frame(by_enum_completion) || !nrow(by_enum_completion)) return("")

    enum_vec <- if (!is.null(findings) && nrow(findings) && "enumerator_display" %in% names(findings)) {
        as.character(findings$enumerator_display)
    } else character()
    enum_vec <- enum_vec[!is.na(enum_vec) & nzchar(enum_vec)]
    issue_counts <- if (length(enum_vec)) {
        tibble::tibble(enumerator = enum_vec) %>% dplyr::count(enumerator, name = "n_issues")
    } else tibble::tibble(enumerator = character(), n_issues = integer())

    # Number of days: distinct calendar days that enumerator has any row in
    # the data.
    days_tbl <- if (!is.null(ds) && !is.null(roles$enum) && !is.na(roles$enum) && roles$enum %in% names(ds) &&
                    !is.null(roles$start) && !is.na(roles$start) && roles$start %in% names(ds)) {
        enum_disp_ds <- resolve_display_vec(
        ds[[roles$enum]], resolve_unit_name(ds, roles$enum, roles$enum_name),
        roles$enumerator_display %||% "name"
        )
        day <- suppressWarnings(as.Date(as.character(ds[[roles$start]])))
        tibble::tibble(enumerator = as.character(enum_disp_ds), day = day) %>%
        dplyr::filter(!is.na(enumerator), nzchar(enumerator), !is.na(day)) %>%
        dplyr::distinct(enumerator, day) %>%
        dplyr::count(enumerator, name = "n_days")
    } else tibble::tibble(enumerator = character(), n_days = integer())

    out <- by_enum_completion %>%
        dplyr::transmute(enumerator = as.character(enumerator), completed_surveys = n_complete) %>%
        dplyr::left_join(days_tbl, by = "enumerator") %>%
        dplyr::left_join(issue_counts, by = "enumerator")
    out$n_days[is.na(out$n_days)] <- 0L
    out$n_issues[is.na(out$n_issues)] <- 0L
    out$rate <- ifelse(out$completed_surveys > 0, round(out$n_issues / out$completed_surveys, 2), NA_real_)
    out <- out %>% dplyr::arrange(dplyr::desc(rate))
    out <- out[, c("enumerator", "n_days", "completed_surveys", "n_issues", "rate")]

    col_labels <- list(enumerator = "Enumerator", n_days = "Number of days",
                        completed_surveys = "Completed surveys", n_issues = "Number of issues", rate = "Rate")
    paste0(
        "<h3>Enumerators</h3>",
        html_searchable_table(out, names(out), table_id, 10L, col_labels = col_labels)
    )
}

#' Renders one or more searchable tables for `sub`'s findings, splitting
#' into separate tables only when the categories present need different
#' columns. Never splits by enumerator — that's All Issues' job alone.
render_findings_tables <- function(sub, id_prefix, col_labels, show_n = 10L) {
    if (is.null(sub) || nrow(sub) == 0) {
        return(html_searchable_table(sub, DEFAULT_FINDINGS_COLS, id_prefix, show_n, col_labels = col_labels))
    }
    col_sig <- vapply(sub$category, function(cg) paste(CATEGORY_COLS[[cg]] %||% DEFAULT_FINDINGS_COLS, collapse = "|"), character(1))
    sigs <- unique(col_sig)
    if (length(sigs) <= 1) {
        cols <- CATEGORY_COLS[[sub$category[[1]]]] %||% DEFAULT_FINDINGS_COLS
        return(html_searchable_table(sub, cols, id_prefix, show_n, col_labels = col_labels))
    }
    esc <- function(x) {
        x <- as.character(x); x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE); x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    parts <- character()
    for (i in seq_along(sigs)) {
        grp_df <- sub[col_sig == sigs[i], , drop = FALSE]
        cols <- CATEGORY_COLS[[grp_df$category[[1]]]] %||% DEFAULT_FINDINGS_COLS
        lbl <- category_label(grp_df$category[[1]])
        sub_id <- paste0(id_prefix, "-", i)
        body <- html_searchable_table(grp_df, cols, sub_id, show_n, col_labels = col_labels)
        parts <- c(parts, paste0("<h4>", esc(lbl), "</h4>"), body)
    }
    paste(parts, collapse = "")
}

# Title above a module's own findings table — default "Issues," with
# per-module overrides. Field Request (M9) already has its own "Info"/"N
# entries" vocabulary and is excluded here.
findings_table_title <- function(meta_mod) {
    if (!is.null(meta_mod$issue_col_label)) return(NULL)
    meta_mod$findings_title %||% "Issues"
}

render_findings_tables_titled <- function(sub, id_prefix, col_labels, meta_mod, show_n = 10L) {
    if (is.null(sub) || nrow(sub) == 0) return("")
    table_html <- render_findings_tables(sub, id_prefix, col_labels, show_n)
    title <- findings_table_title(meta_mod)
    if (is.null(title)) return(table_html)
    esc_title <- gsub("&", "&amp;", title, fixed = TRUE)
    paste0("<h3>", esc_title, "</h3>", table_html)
}

SUMMARY_PLACEHOLDER_TEXT <- "Summary not yet drafted. Findings are listed below by module."

# Reads the agent-drafted Summary narrative (hfc/config/summary_message.md).
read_summary_message <- function(code_output_dir) {
    path <- hfc_path(code_output_dir, "config", "summary_message.md")
    if (!file.exists(path)) return(NA_character_)
    txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
    if (!nzchar(trimws(txt))) return(NA_character_)
    txt
}

# Converts the Summary narrative's plain-text markdown-lite (numbered lines,
# "- " bullets, blank-line-separated prose) into real <ol>/<ul>/<p> markup.
render_summary_narrative <- function(txt) {
    esc <- function(x) {
        x <- as.character(x)
        x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE)
        x <- gsub("<", "&lt;", x, fixed = TRUE)
        x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    lines <- trimws(strsplit(txt, "\n", fixed = TRUE)[[1]])

    blocks <- list()
    buf <- character()
    buf_type <- NA_character_

    flush <- function() {
        if (!length(buf)) return(invisible())
        html <- if (identical(buf_type, "ol")) {
            paste0("<ol>", paste0("<li>", esc(buf), "</li>", collapse = ""), "</ol>")
        } else if (identical(buf_type, "ul")) {
            paste0("<ul>", paste0("<li>", esc(buf), "</li>", collapse = ""), "</ul>")
        } else {
            paste0("<p>", paste(esc(buf), collapse = "<br/>"), "</p>")
        }
        blocks[[length(blocks) + 1]] <<- html
        buf <<- character()
        buf_type <<- NA_character_
    }

    for (ln in lines) {
        if (!nzchar(ln)) { flush(); next }
        is_ol <- grepl("^\\d+\\.\\s+", ln)
        is_ul <- !is_ol && grepl("^-\\s+", ln)
        item_type <- if (is_ol) "ol" else if (is_ul) "ul" else "p"
        item_text <- if (is_ol) sub("^\\d+\\.\\s+", "", ln) else if (is_ul) sub("^-\\s+", "", ln) else ln
        if (!identical(item_type, buf_type) && length(buf)) flush()
        buf_type <- item_type
        buf <- c(buf, item_text)
    }
    flush()
    paste(unlist(blocks), collapse = "")
}

#' M10 GPS Map: an interactive map plotting every submission with a valid
#' coordinate. Points only render red when the advanced distance flag is on
#' and actually produced findings.
render_gps_map_body <- function(ds, roles, modules, findings = NULL, target_ds = NULL, report_cfg = NULL) {
    esc <- function(x) {
        x <- as.character(x); x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE); x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    xc <- roles$x; yc <- roles$y
    has_gps <- !is.null(roles) && isTRUE(roles$has_gps) && !is.null(ds) &&
        !is.na(xc) && !is.na(yc) && xc %in% names(ds) && yc %in% names(ds)
    if (!has_gps) {
        return("<p class='no-issues'>No GPS coordinates are configured for this survey.</p>")
    }
    map_focus <- tolower(as.character((report_cfg %||% list())$map_focus %||% "country"))
    xx <- safe_num(ds[[xc]])
    yy <- safe_num(ds[[yc]])
    ok <- is.finite(xx) & is.finite(yy)
    idx <- which(ok)
    if (length(idx) > 2000) idx <- sample(idx, 2000)
    ids <- if (".hfc_id_display" %in% names(ds)) ds$.hfc_id_display[idx] else rep("", length(idx))
    ids[is.na(ids)] <- ""
    flagged_ids <- if (!is.null(findings) && "check_module" %in% names(findings)) {
        unique(findings$submission_id[findings$check_module == "M10"])
    } else character()
    flagged <- ids %in% flagged_ids & nzchar(ids)
    n_flagged <- sum(flagged)
    pts_json <- as.character(jsonlite::toJSON(
        data.frame(lat = yy[idx], lon = xx[idx], id = ids, flagged = flagged, stringsAsFactors = FALSE),
        dataframe = "rows", auto_unbox = TRUE
    ))
    pts_json <- gsub("</script", "<\\/script", pts_json, fixed = TRUE)
    zoom <- switch(map_focus, world = 2, city = 11, country = 6, 6)
    center_lat <- if (length(idx)) median(yy[idx], na.rm = TRUE) else 0
    center_lon <- if (length(idx)) median(xx[idx], na.rm = TRUE) else 0
    flag_clause <- if (n_flagged > 0) {
        " Points flagged as distance outliers (an opt-in advanced check for this project) are red."
    } else ""
    paste0(
        "<p class='meta'>Focus: ", esc(map_focus), " · ", length(idx),
        " points (sampled if &gt;2000). Coordinates from ", esc(xc), " / ", esc(yc),
        ". All points with a valid coordinate are shown.", flag_clause,
        " Click a point to see its unique ID.</p>",
        "<div id='gps-map' style='height:420px;border-radius:8px;'></div>",
        "<link rel='stylesheet' href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'/>",
        "<script src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'></script>",
        "<script>(function(){",
        "var map=L.map('gps-map').setView([", center_lat, ",", center_lon, "],", zoom, ");",
        "L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{",
        "attribution:'&copy; OpenStreetMap'}).addTo(map);",
        "var pts=", pts_json, ";",
        "var latlngs=pts.map(function(p){return [p.lat,p.lon];});",
        "pts.forEach(function(p){",
        "L.circleMarker([p.lat,p.lon],{radius:3,color:p.flagged?'#c0392b':'#2a6f5e',fillOpacity:0.7})",
        ".bindPopup('ID: '+(p.id||'(none)')).addTo(map);",
        "});",
        "if(latlngs.length){map.fitBounds(latlngs,{padding:[20,20]});}",
        "})();</script>"
    )
}

#' M12 Balance Tables' custom_html body — see scripts/lib/balance_tables.R
#' for the real implementation (render_balance_tables_body, defined there
#' and sourced alongside this file). This fallback only fires if that file
#' hasn't been sourced for some reason, so a missing dependency degrades to
#' a visible note rather than a build error.
if (!exists("render_balance_tables_body", mode = "function")) {
    render_balance_tables_body <- function(ds, roles, modules, findings = NULL, target_ds = NULL, report_cfg = NULL) {
        "<p class='no-issues'>Balance Tables is on, but scripts/lib/balance_tables.R wasn't loaded.</p>"
    }
}

# Module code -> custom_html renderer.
CUSTOM_HTML_RENDERERS <- list(
    M10 = render_gps_map_body,
    M12 = render_balance_tables_body
)

# The report's top-left title: hardcoded "HFC MM/DD", the same day the file is
# named for (the day it was generated). Deliberately never inferred from the
# project, data, or config.
report_title_label <- function(date = Sys.Date()) paste0("HFC ", format(date, "%m/%d"))

# "Aug 17" / "May 09": abbreviated month + zero-padded day, the one date
# format the summary messages use (never 08/17). Locale-independent.
format_summary_date <- function(x) {
    d <- suppressWarnings(as.Date(as.character(x)))
    ifelse(is.na(d), NA_character_, paste(month.abb[as.integer(format(d, "%m"))], format(d, "%d")))
}

# Warns (never errors) when a summary message uses a relative day
# ("today"), a numeric date, or doesn't name the last data-collection day;
# also checks the condensed message's "Issues to highlight:" list (see
# lint_condensed_issues()).
lint_summary_messages <- function(code_output_dir, last_date, findings = NULL, primary_known = FALSE) {
    want <- format_summary_date(last_date)
    for (f in c("summary_message.md", "summary_condensed.md")) {
        path <- hfc_path(code_output_dir, "config", f)
        if (!file.exists(path)) next
        txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
        if (grepl("\\b(today|today's|yesterday|tonight)\\b", txt, ignore.case = TRUE)) {
            message("WARNING: ", f, " uses a relative day (today/yesterday). Name the actual day instead, e.g. ", want %||% "Aug 17", ".")
        }
        if (grepl("\\b\\d{1,2}/\\d{1,2}\\b|\\b\\d{4}-\\d{2}-\\d{2}\\b", txt)) {
            message("WARNING: ", f, " uses a numeric date. Use the 'Mon DD' form (e.g. ", want %||% "Aug 17", ").")
        }
        if (isTRUE(primary_known) && !(grepl("primary samples attempted (submitted)", txt, fixed = TRUE) &&
                                       grepl("completion so far", txt, fixed = TRUE))) {
            message("WARNING: ", f, " doesn't state cumulative completion in the four-sentence pattern. A primary sample is known, so include '<A> primary samples attempted (submitted), that is <Z>% completion so far!' (see assets/summary_condensed_example.md).")
        }
        if (!is.na(want) && !grepl(want, txt, fixed = TRUE)) {
            message("WARNING: ", f, " never names the last day of data collection (", want, ").")
        }
    }
    lint_condensed_issues(code_output_dir, last_date, findings)
    invisible(NULL)
}

# Warns when the condensed message's "Issues to highlight:" list is missing,
# too short or too long for the last day's findings (2-5 items when 2+ issues
# exist; the single issue when only 1 exists; absent only when none exist).
lint_condensed_issues <- function(code_output_dir, last_date, findings) {
    path <- hfc_path(code_output_dir, "config", "summary_condensed.md")
    if (!file.exists(path) || is.null(findings) || is.na(last_date %||% NA_character_)) return(invisible(NULL))
    n_day <- if (nrow(findings) && "date_display" %in% names(findings)) sum(findings$date_display == last_date, na.rm = TRUE) else 0L
    lines <- readLines(path, warn = FALSE)
    at <- grep("^\\s*Issues to highlight:\\s*$", lines)
    n_items <- if (length(at)) {
        rest <- lines[(at[[1]] + 1):length(lines)]
        sum(grepl("^\\s*\\d+\\.\\s", rest))
    } else 0L
    if (n_day > 0 && n_items == 0) {
        message("WARNING: summary_condensed.md has no 'Issues to highlight:' list, but ", n_day, " issue(s) were found on ", format_summary_date(last_date) %||% last_date, ". List 2 to 5.")
    } else if (n_day >= 2 && n_items < 2) {
        message("WARNING: summary_condensed.md highlights only ", n_items, " issue(s); list at least 2 (", n_day, " were found on ", format_summary_date(last_date) %||% last_date, ").")
    } else if (n_items > 5) {
        message("WARNING: summary_condensed.md highlights ", n_items, " issues; 5 is the cap.")
    }
    invisible(NULL)
}

CONDENSED_PLACEHOLDER_TEXT <- "Condensed summary not yet drafted."

# Completion (M1) column labels: the project's own group label for the
# "Group" column. Shared by the detailed and condensed reports.
m1_col_labels <- function(col_labels, roles, modules) {
    col_labels["group"] <- roles$group_label %||% "Group"
    col_labels
}

# The one-sentence statement of how Completion is computed, shown under the
# Completion heading in both reports. Which formula applies depends on whether
# the Overall table has a "Submitted (Primary Sample)" column (n_primary), i.e.
# whether a primary sample is known.
completion_explanation <- function(m1_overall) {
    if (!is.null(m1_overall) && "n_primary" %in% names(m1_overall)) {
        "Completion = the number of completed surveys (primary or replacement) divided by the number of primary samples attempted (submitted). It can exceed 100% when replacements completed for primary respondents who never submitted."
    } else {
        "Completion = the number of completed surveys divided by the number of surveys submitted (no primary sample is defined for this project)."
    }
}

# The three sections the condensed report carries under its message, as plain
# cards (no ids, no nav links): Completion (the formula sentence, then overall /
# by enumerator / by date only), Duplicates (the issues table; omitted when
# there are none) and Form Version (the version summary AND the issues table
# when form version issues exist, otherwise just "No form version issues
# found!"). `findings` must already
# carry the *_display columns prepared in write_html_report().
render_condensed_sections <- function(findings, stats, modules, roles, findings_col_labels) {
    card <- function(mod, body) {
        if (!nzchar(body)) return("")
        paste0("<section class='card'><h2>", module_label(mod), "</h2>", body, "</section>")
    }
    on <- function(mod) is.null(modules) || is.null(modules[[mod]]) || !isFALSE(modules[[mod]]$on)

    m1 <- if (on("M1") && !is.null(stats$M1)) {
        keep <- stats$M1[intersect(c("overall", "by_enumerator", "by_date"), names(stats$M1))]
        paste0("<p class='mod-desc'>", completion_explanation(stats$M1$overall), "</p>",
               render_stats_block(keep, "m1", col_labels = m1_col_labels(STATS_COL_LABELS[["M1"]], roles, modules)))
    } else ""

    m2 <- if (on("M2") && !is.null(findings) && nrow(findings) && "check_module" %in% names(findings)) {
        sub <- findings[findings$check_module == "M2", , drop = FALSE]
        render_findings_tables_titled(sub, "tbl-cond-m2", findings_col_labels, MODULE_META[["M2"]])
    } else ""

    m3 <- if (on("M3") && !is.null(stats$M3)) {
        m3_findings <- if (!is.null(findings) && nrow(findings) && "check_module" %in% names(findings)) {
            findings[findings$check_module == "M3", , drop = FALSE]
        } else NULL
        if (!is.null(m3_findings) && nrow(m3_findings)) {
            findings_labels <- findings_col_labels
            paste0(render_stats_block(stats$M3, "m3", col_labels = STATS_COL_LABELS[["M3"]]),
                   render_findings_tables_titled(m3_findings, "tbl-cond-m3", findings_labels, MODULE_META[["M3"]]))
        } else "<p class='no-issues'>No form version issues found!</p>"
    } else ""

    paste0(card("M1", m1), card("M2", m2), card("M3", m3))
}

# Reads the agent-drafted condensed message (hfc/config/summary_condensed.md).
read_condensed_message <- function(code_output_dir) {
    path <- hfc_path(code_output_dir, "config", "summary_condensed.md")
    if (!file.exists(path)) return(NA_character_)
    txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
    if (!nzchar(trimws(txt))) return(NA_character_)
    txt
}

# Renders the condensed message: same markdown-lite as the long narrative,
# with each label paragraph ("Enumerators on Aug 17:", "Issues to highlight:")
# set in bold.
render_condensed_narrative <- function(txt) {
    html <- render_summary_narrative(txt)
    gsub("<p>([^<]{1,80}:)</p>", "<p class='label'><strong>\\1</strong></p>", html)
}

# The condensed report: one page with the condensed message followed by the
# few trimmed sections in `sections_html`. The header is just the title - no
# nav, About, or clickable section titles.
condensed_report_html <- function(message_txt, report_title = report_title_label(), sections_html = "") {
    body <- if (!is.na(message_txt)) {
        render_condensed_narrative(message_txt)
    } else {
        paste0("<p class='placeholder'><em>", CONDENSED_PLACEHOLDER_TEXT, "</em></p>")
    }
    paste0(
"<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'/>",
"<meta name='viewport' content='width=device-width, initial-scale=1'/>",
"<title>", report_title, "</title><style>
:root{--bg:#f4efe6;--ink:#1c1914;--muted:#5c564c;--card:#fffdf8;--line:#ddd4c4;--accent:#2a6f5e;--page-w:1000px;--page-pad:1.25rem}
*{box-sizing:border-box}
body{margin:0;font-family:'Source Serif 4',Georgia,serif;background:var(--bg);color:var(--ink);line-height:1.6;font-size:1.05rem}
header.top{max-width:var(--page-w);margin:0 auto;padding:1.4rem var(--page-pad) 0;font-family:'IBM Plex Sans',system-ui,sans-serif;font-weight:600;font-size:1.05rem;letter-spacing:.02em}
main{max-width:var(--page-w);margin:0 auto;padding:1.2rem var(--page-pad) 3rem}
.message{max-width:760px;background:var(--card);border:1px solid var(--line);border-left:4px solid var(--accent);border-radius:10px;padding:1.6rem 1.9rem}
.message p{margin:0 0 1.5rem}
.message p.label{margin:0 0 .5rem;font-family:'IBM Plex Sans',system-ui,sans-serif}
.message ul,.message ol{margin:0 0 1.5rem;padding-left:1.4rem}
.message li{margin:.4rem 0}
.message > :last-child{margin-bottom:0}
.placeholder{color:var(--muted)}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:1rem 1.2rem;margin:1.4rem 0}
.card h2{font-size:1.15rem;margin:.1rem 0 .6rem}
.card h3{font-size:1rem;margin:.8rem 0 .3rem}
.card h4{font-size:.85rem;font-family:'IBM Plex Sans',system-ui,sans-serif;font-weight:600;color:var(--muted);margin:1rem 0 .35rem;text-transform:uppercase;letter-spacing:.03em}
.meta{color:var(--muted);font-size:.95rem}
", REPORT_TABLE_CSS, "</style>
<link href='https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600&family=Source+Serif+4:opsz,wght@8..60,500;8..60,700&display=swap' rel='stylesheet'/>
</head><body><header class='top'>", report_title, "</header><main><div class='message'>", body, "</div>", sections_html, "</main>", REPORT_TABLE_JS, "</body></html>")
}

# Path of the detailed copy of a report: a `detailed/` subfolder next to it,
# with "_detailed" before the extension (<MMDD>_HFCs.html ->
# detailed/<MMDD>_HFCs_detailed.html).
detailed_report_path <- function(html_path) {
    file.path(dirname(html_path), "detailed", sub("\\.html$", "_detailed.html", basename(html_path)))
}

# Table styles and behaviour (search box, Show all toggle) shared by the
# detailed report and the condensed page.
REPORT_TABLE_CSS <- ".table-toolbar{display:flex;flex-wrap:wrap;gap:.6rem;align-items:center;margin:0 0 .6rem}
.table-search{flex:1;min-width:12rem;padding:.45rem .65rem;border:1px solid var(--line);border-radius:6px;
  font-family:'IBM Plex Sans',system-ui,sans-serif;font-size:.9rem}
.table-count{font-size:.82rem;color:var(--muted);font-family:'IBM Plex Sans',system-ui,sans-serif}
.table-toggle{padding:.4rem .75rem;border:1px solid var(--accent);border-radius:6px;background:#fff;
  color:var(--accent);font-family:'IBM Plex Sans',system-ui,sans-serif;font-size:.82rem;font-weight:600;cursor:pointer}
.table-toggle:hover{background:var(--accent);color:#fff}
table.searchable{border-collapse:collapse;width:100%;background:#fff;font-size:.9rem}
table.searchable th,table.searchable td{border:1px solid var(--line);padding:.4rem .55rem;text-align:left;vertical-align:top}
table.searchable th{background:#ebe3d4;font-family:'IBM Plex Sans',system-ui,sans-serif;font-weight:600}
tr.row-hidden{display:none}
tr.match-show{display:table-row}
"
REPORT_TABLE_JS <- "<script>
(function(){
  function applySearch(input){
    var id=input.getAttribute('data-table');
    var table=document.getElementById(id);
    if(!table) return;
    var wrap=document.getElementById(id+'-wrap');
    var btn=document.querySelector('.table-toggle[data-table=\"'+id+'\"]');
    var expanded=btn && btn.getAttribute('data-expanded')==='true';
    var showN=wrap?parseInt(wrap.getAttribute('data-collapsed-n')||'10',10):10;
    var q=(input.value||'').toLowerCase().trim();
    var rows=[].slice.call(table.tBodies[0].rows);
    var shown=0;
    rows.forEach(function(tr,i){
      var text=tr.textContent.toLowerCase();
      var visible;
      if(q){
        visible=text.indexOf(q)!==-1;
        tr.classList.toggle('match-show', visible);
      } else {
        tr.classList.remove('match-show');
        visible=expanded || i<showN;
      }
      tr.classList.toggle('row-hidden', !visible);
      if(visible) shown++;
    });
    var count=document.querySelector('.table-count[data-for=\"'+id+'\"]');
    if(count) count.textContent=shown+' of '+rows.length+(q?' matching':' shown');
  }
  document.querySelectorAll('.table-search').forEach(function(inp){
    inp.addEventListener('input', function(){ applySearch(inp); });
  });
  document.querySelectorAll('.table-toggle').forEach(function(btn){
    btn.addEventListener('click', function(){
      var id=btn.getAttribute('data-table');
      var wrap=document.getElementById(id+'-wrap');
      var expanded=btn.getAttribute('data-expanded')==='true';
      if(expanded){
        btn.setAttribute('data-expanded','false');
        btn.textContent='Show all';
        if(wrap) wrap.setAttribute('data-collapsed-n','15');
      } else {
        btn.setAttribute('data-expanded','true');
        btn.textContent='Show top 15';
      }
      var input=document.querySelector('.table-search[data-table=\"'+id+'\"]');
      if(input){ input.value=''; applySearch(input); }
    });
  });
  function openDetailsTarget(){
    var h=location.hash;
    if(!h) return;
    var el=document.querySelector(h);
    if(el && el.tagName==='DETAILS'){ el.open=true; el.scrollIntoView(); }
  }
  window.addEventListener('hashchange', openDetailsTarget);
  window.addEventListener('DOMContentLoaded', openDetailsTarget);
  openDetailsTarget();
})();
</script>"

write_html_report <- function(findings, code_output_dir, project_id, open = FALSE,
                                    roles = NULL, ds = NULL, report_cfg = NULL,
                                    module_notes = NULL, stats = NULL, modules = NULL,
                                    target_ds = NULL) {
        suppressPackageStartupMessages({ library(dplyr) })
        report_dir <- hfc_path(code_output_dir, "outputs")
        dir.create(report_dir, showWarnings = FALSE, recursive = TRUE)
        # Dated per build so successive reports accumulate as separate
        # snapshots instead of overwriting the last one.
        html_path <- file.path(report_dir, paste0(format(Sys.Date(), "%m%d"), "_HFCs.html"))

        esc <- function(x) {
            x <- as.character(x)
            x[is.na(x)] <- ""
            x <- gsub("&", "&amp;", x, fixed = TRUE)
            x <- gsub("<", "&lt;", x, fixed = TRUE)
            x <- gsub(">", "&gt;", x, fixed = TRUE)
            x
        }

        if (!is.null(ds) && !is.null(roles)) {
            ds$.hfc_id_display <- composite_id_string(ds, roles$entity_id, roles$entity_id_sep %||% " / ")
        }

        stats <- stats %||% list()
        last_date <- roles$last_date %||% NA_character_
        if (!is.null(last_date) && (is.na(last_date) || !nzchar(last_date))) last_date <- NA_character_

        entity_label <- roles$entity_label %||% "Entity ID"
        group_label <- roles$group_label %||% "Group"
        arm_label <- roles$treatment_control_label %||% "Treatment Arm"
        findings_col_labels <- list(
            date_display = "Date", entity_display = entity_label, group_display = group_label,
            enumerator_display = "Enumerator", issue = "Issue", value = "Value", variable_display = "Variable",
            arm_display = arm_label
        )

        findings <- sort_findings_for_display(findings)
        findings$date_display <- finding_date_vec(findings)
        findings$entity_display <- resolve_display_vec(findings$submission_id, findings$entity_name, roles$entity_display %||% "id")
        findings$group_display <- resolve_display_vec(findings$group_id, findings$group_name, roles$group_display %||% "name")
        findings$enumerator_display <- resolve_display_vec(findings$enumerator, findings$enumerator_name, roles$enumerator_display %||% "name")
        findings$arm_display <- resolve_display_vec(findings$arm_id, NULL, "id")
        findings$variable_display <- var_label(findings$variable, roles)

        # "By category" counts only the last day's own issues, not the
        # cumulative total.
        by_mod <- if (nrow(findings) && "check_module" %in% names(findings) && !is.na(last_date)) {
            findings %>% filter(date_display == last_date) %>% count(check_module, sort = TRUE)
        } else tibble(check_module = character(), n = integer())

        summary_cards <- if (nrow(by_mod)) {
            paste0(
            "<div class='cards'>",
            paste0("<div class='stat'><div class='stat-n'>", by_mod$n,
                    "</div><div class='stat-l'>", esc(module_label(by_mod$check_module)), "</div></div>",
                    collapse = ""),
            "</div>"
            )
        } else ""

        summary_msg <- read_summary_message(code_output_dir)
        summary_msg_html <- if (!is.na(summary_msg)) {
            paste0("<div class='summary-narrative'>", render_summary_narrative(summary_msg), "</div>")
        } else {
            paste0("<div class='summary-narrative summary-placeholder'><em>", esc(SUMMARY_PLACEHOLDER_TEXT), "</em></div>")
        }

        modules_present <- compute_modules_present(findings, stats, modules)

        mod_sections <- character()
        nav_links <- c('<a href="#about">About</a>', '<a href="#summary">Summary</a>')
        if (!is.na(last_date)) nav_links <- c(nav_links, '<a href="#lastday">Last Day</a>')

        for (mod in modules_present) {
            meta_mod <- MODULE_META[[mod]] %||% list()
            content_type <- meta_mod$content_type %||% "findings"
            sub <- findings %>% filter(check_module == mod)
            other_sub <- NULL
            if (identical(mod, "M9")) {
            # Only rows explicitly tagged category == "field_request" stay
            # in M9's own Info table; everything else renders in "Other".
            is_fr <- !is.na(sub$category) & sub$category == "field_request"
            other_sub <- sub %>% filter(!is_fr)
            sub <- sub %>% filter(is_fr)
            }
            aid <- paste0("mod-", tolower(mod))
            nav_links <- c(nav_links, sprintf(
            '<a href="#%s">%s <sup class="mod-code">%s</sup></a>', aid, esc(module_label(mod)), esc(mod)
            ))
            desc_override <- module_notes$overrides[[mod]]
            desc_text <- if (!is.null(desc_override) && nzchar(desc_override)) desc_override else module_desc(mod, modules)
            desc_html <- if (nzchar(desc_text)) paste0("<p class='mod-desc'>", esc(desc_text), "</p>") else ""
            if (identical(mod, "M1")) {
                desc_html <- paste0(desc_html, "<p class='mod-desc'>", esc(completion_explanation(stats$M1$overall)), "</p>")
            }
            custom_html <- ""
            if (identical(mod, "M9") && length(module_notes$custom)) {
            items <- vapply(names(module_notes$custom), function(nm) {
                entry <- module_notes$custom[[nm]]
                lbl <- entry$label %||% nm
                d <- entry$description %||% ""
                paste0("<li><strong>", esc(lbl), "</strong>: ", esc(d), "</li>")
            }, character(1))
            custom_html <- paste0(
                "<div class='custom-checks'><h3>Custom checks for this survey</h3><ul>",
                paste(items, collapse = ""), "</ul></div>"
            )
            }
            col_labels_mod <- STATS_COL_LABELS[[mod]]
            if (identical(mod, "M1")) col_labels_mod <- m1_col_labels(col_labels_mod, roles, modules)
            # Per-module override of the findings table's "Issue" column
            # label and the "N issues found" heading noun (report_sections.
            # json: Field Request reads "Info"/"entries" instead) — a
            # per-call copy, never mutating the shared findings_col_labels
            # used by Last Day/All Issues, which always say "Issue" even for
            # Field-Request-sourced rows there.
            col_labels_findings <- findings_col_labels
            if (!is.null(meta_mod$issue_col_label)) col_labels_findings$issue <- meta_mod$issue_col_label
            count_noun <- meta_mod$count_noun %||% "issues found"
            no_issues_word <- meta_mod$no_issues_word %||% "No issues found!"

            stats_html <- if (identical(content_type, "custom_html")) "" else {
            render_stats_block(stats[[mod]], tolower(mod), col_labels = col_labels_mod)
            }
            is_stats_only <- identical(content_type, "stats")
            heading_suffix <- if (nrow(sub) == 0) "" else paste0(" · ", nrow(sub), " ", count_noun)
            body_html <- if (identical(content_type, "custom_html")) {
            renderer <- CUSTOM_HTML_RENDERERS[[mod]]
            custom_body <- if (!is.null(renderer)) {
                renderer(ds, roles, modules, findings = findings, target_ds = target_ds, report_cfg = report_cfg)
            } else ""
            findings_tbl <- render_findings_tables_titled(sub, paste0("tbl-", aid), col_labels_findings, meta_mod)
            paste0(custom_body, findings_tbl)
            } else if (is_stats_only) {
            findings_tbl <- render_findings_tables_titled(sub, paste0("tbl-", aid), col_labels_findings, meta_mod)
            paste0(stats_html, findings_tbl)
            } else if (nrow(sub) == 0) {
            paste0(stats_html, "<p class='no-issues'>", esc(no_issues_word), "</p>")
            } else {
            paste0(stats_html, render_findings_tables_titled(sub, paste0("tbl-", aid), col_labels_findings, meta_mod))
            }
            mod_sections <- c(mod_sections, paste0(
            "<section id='", aid, "' class='card'><h2>", esc(module_label(mod)),
            " <span class='mod-code'>", esc(mod), "</span>", heading_suffix,
            "</h2>", desc_html, custom_html, body_html, "</section>"
            ))

            # "Other" — every M9 custom-check finding that isn't itself a
            # field_request row.
            if (identical(mod, "M9")) {
            other_n <- if (is.null(other_sub)) 0L else nrow(other_sub)
            other_heading <- if (other_n == 0) "" else paste0(" · ", other_n, " issues found")
            other_tbl <- if (other_n == 0) {
                "<p class='no-issues'>No issues found!</p>"
            } else {
                paste0("<h3>Issues</h3>", render_findings_tables(other_sub, "tbl-other", findings_col_labels))
            }
            other_desc <- other_section_desc(other_sub, module_notes$custom)
            nav_links <- c(nav_links, '<a href="#other">Other</a>')
            mod_sections <- c(mod_sections, paste0(
                "<section id='other' class='card'><h2>Other", other_heading, "</h2>",
                "<p class='mod-desc'>", esc(other_desc), "</p>",
                other_tbl, "</section>"
            ))
            }
        }

    lastday_html <- ""
    if (!is.na(last_date)) {
        last_day_f <- if (nrow(findings)) {
        fdv <- finding_date_vec(findings)
        findings[!is.na(fdv) & fdv == last_date, , drop = FALSE]
        } else findings
        lastday_duration_html <- ""
        dc <- modules$M4$duration %||% roles$duration %||% NA_character_
        if (!is.null(ds) && !is.na(dc) && dc %in% names(ds) && !is.na(roles$start) && roles$start %in% names(ds)) {
        day_d <- suppressWarnings(as.Date(as.character(ds[[roles$start]])))
        day_rows <- ds[!is.na(day_d) & as.character(day_d) == last_date, , drop = FALSE]
        dur_day <- clean_num(day_rows[[dc]], na_codes_for(modules, dc)) / 60
        ok_day <- is.finite(dur_day)
        if (any(ok_day)) {
            lastday_duration_html <- render_stats_block(
            list(`Survey duration on this day` = tibble(
                date = last_date,
                min = round1(min(dur_day[ok_day])), median = round1(stats::median(dur_day[ok_day])),
                mean = round1(mean(dur_day[ok_day])), max = round1(max(dur_day[ok_day])),
                sd = round1(stats::sd(dur_day[ok_day])), n = sum(ok_day)
            )),
            "lastday-duration", col_labels = STATS_COL_LABELS[["M4"]]
            )
        }
        }
        lastday_html <- paste0(
        "<section id='lastday' class='card'><h2>Last Day: ", esc(last_date), "</h2>",
        "<p class='mod-desc'>Every issue from the most recent day of data collection, across all modules: ",
        "a quick way to see what's most urgent.</p>",
        lastday_duration_html,
        "<h3>Issues</h3>",
        html_searchable_table(
            last_day_f,
            ALL_FINDINGS_COLS,
            "tbl-lastday", 15L,
            col_labels = findings_col_labels
        ),
        "</section>"
        )
    }

    nav_links <- c(nav_links, '<a href="#all">All issues</a>')
    all_tbl <- html_searchable_table(
        findings,
        ALL_FINDINGS_COLS,
        "tbl-all", 10L,
        col_labels = findings_col_labels
    )
    all_enum_table_html <- render_all_issues_enumerator_table(findings, stats, ds, roles)
    all_by_enum_html <- render_all_issues_by_enumerator(findings, findings_col_labels)

    # Glossary shows only terms that can actually appear given which
    # modules are on.
    glossary_all <- list(
        Finding = c("Issue", "One flagged row: a single thing that looks off in one submission (or one enumerator/site) and may be worth a closer look."),
        Category = c("Category", "A short label grouping similar findings together, e.g. \"irregular_time\" or \"gps_distance\"."),
        Consent = c("Consent", "The guardian or head-of-household's agreement for the interview to take place."),
        Assent = c("Assent", "The child's own agreement to participate, separate from and in addition to a guardian's consent."),
        Enumerator = c("Enumerator", "The field staff member who conducted the interview."),
        Duplicate = c("Duplicate ID / key", "Two or more submissions sharing the same unique ID (or ID combination) or survey key, usually meaning one interview was captured twice."),
        Outlier = c("Outlier", "A value far outside the typical range for that question: possibly a data-entry slip, possibly a genuinely unusual case."),
        Straightlining = c("Straightlining", "Giving the same answer choice repeatedly instead of varying answers, by one enumerator across surveys, or within one survey's set of similar questions."),
        LastDay = c("Last day", "The most recent date of data collection, confirmed at setup, collected in its own Last Day tab.")
    )
    glossary_keys <- c(
        "Finding", "Category",
        if ("M14" %in% modules_present) c("Consent", "Assent"),
        "Enumerator",
        if ("M2" %in% modules_present) "Duplicate",
        if ("M6" %in% modules_present) "Outlier",
        if ("M8" %in% modules_present) "Straightlining",
        if (!is.na(last_date)) "LastDay"
    )
    glossary_terms <- glossary_all[glossary_keys]
    glossary_html <- paste0(
        "<dl class='glossary'>",
        paste0(vapply(glossary_terms, function(t) paste0(
        "<dt>", esc(t[1]), "</dt><dd>", esc(t[2]), "</dd>"
        ), character(1)), collapse = ""),
        "</dl>"
    )
    about_html <- paste0(
        "<section id='about' class='card'><h2>About this dashboard</h2>",
        "<p>This report is a first read of the data, not a verdict. The tables below ", 
        "are not necessarily proof that something is wrong, but results of an analysis ", 
        "that can be reviewed BUT is first AI-assisted (to err is also AI). Use the search box (or ",
        "\"Show all\") in any table to look up a specific submission, enumerator, or value.</p>",
        "<p><strong>Terms you'll see:</strong></p>",
        glossary_html,
        "</section>"
    )

    html <- paste0(
        "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'/>",
        "<meta name='viewport' content='width=device-width, initial-scale=1'/>",
        "<title>", report_title_label(), "</title>",
        "<style>
:root{--bg:#f4efe6;--ink:#1c1914;--muted:#5c564c;--card:#fffdf8;--line:#ddd4c4;--accent:#2a6f5e;--nav:#1a222c}
*{box-sizing:border-box}
body{margin:0;font-family:'Source Serif 4',Georgia,serif;background:var(--bg);color:var(--ink);line-height:1.45}
header.nav{position:sticky;top:0;z-index:50;background:var(--nav);color:#e7eef5;
  display:flex;flex-wrap:wrap;gap:.75rem 1.1rem;align-items:center;
  padding:.7rem 1.25rem;border-bottom:1px solid #2d3a47}
header.nav .brand{font-weight:600;letter-spacing:.02em;margin-right:.5rem}
header.nav a{color:#c9d6e2;text-decoration:none;font-family:'IBM Plex Sans',system-ui,sans-serif;font-size:.88rem}
header.nav a:hover{color:#fff}
main{max-width:1100px;margin:0 auto;padding:1.5rem 1.25rem 3rem}
h1{font-size:clamp(1.6rem,3vw,2.1rem);margin:.2rem 0 .35rem}
.meta{color:var(--muted);font-size:.95rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:1rem 1.2rem;margin:1.1rem 0}
.cards{display:flex;flex-wrap:wrap;gap:.75rem;margin:1rem 0}
.stat{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:.7rem 1rem;min-width:5.5rem}
.stat-n{font-size:1.35rem;font-weight:700;color:var(--accent)}
.stat-l{font-size:.8rem;color:var(--muted);font-family:'IBM Plex Sans',system-ui,sans-serif}
", REPORT_TABLE_CSS, ".mod-code{font-size:.68rem;color:var(--muted);font-family:'IBM Plex Sans',system-ui,sans-serif;
  font-weight:400;margin-left:.35rem;vertical-align:middle}
h2 .mod-code{font-size:.62rem;border:1px solid var(--line);border-radius:4px;padding:.05rem .35rem}
.mod-desc{color:var(--muted);font-size:.95rem;margin:.15rem 0 .9rem}
.no-issues{color:var(--accent);font-weight:600;font-size:.9rem;margin:.4rem 0}
.card h4{font-size:.85rem;font-family:'IBM Plex Sans',system-ui,sans-serif;font-weight:600;
  color:var(--muted);margin:1rem 0 .35rem;text-transform:uppercase;letter-spacing:.03em}
dl.glossary{display:grid;grid-template-columns:max-content 1fr;gap:.25rem 1rem;margin:.4rem 0 0}
dl.glossary dt{font-weight:600;font-family:'IBM Plex Sans',system-ui,sans-serif;font-size:.9rem}
dl.glossary dd{margin:0 0 .5rem;color:var(--muted);font-size:.9rem}
.custom-checks{margin:.4rem 0 1rem;padding:.6rem .8rem;background:#f7f1e4;border:1px solid var(--line);border-radius:8px}
.custom-checks h3{margin:0 0 .3rem;font-size:.95rem;font-family:'IBM Plex Sans',system-ui,sans-serif}
.custom-checks ul{margin:0;padding-left:1.1rem}
.custom-checks li{margin:.25rem 0;color:var(--muted);font-size:.9rem}
.summary-narrative{margin:.4rem 0 1rem;padding:.75rem 1rem;background:var(--card);border-left:4px solid var(--accent, #3d9a7a);border-radius:6px;line-height:1.5}
.summary-placeholder{color:var(--muted);border-left-color:var(--line)}
.stats-index{margin:.3rem 0 .8rem;font-size:.85rem;color:var(--muted)}
.stats-index a{color:var(--accent);text-decoration:none}
.stats-index a:hover{text-decoration:underline}
details.stats-details{margin:.5rem 0}
details.stats-details summary{cursor:pointer;font-weight:600;padding:.3rem 0;font-family:'IBM Plex Sans',system-ui,sans-serif}
details.enum-issues{margin:.5rem 0;border-top:1px solid var(--line);padding-top:.5rem}
details.enum-issues summary{cursor:pointer;font-weight:600;padding:.3rem 0;font-family:'IBM Plex Sans',system-ui,sans-serif}
details.enum-issues summary .meta{font-weight:400;color:var(--muted);font-size:.85rem}
footer.note{margin-top:1.5rem;color:var(--muted);font-size:.9rem}
</style>
<link href='https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600&family=Source+Serif+4:opsz,wght@8..60,500;8..60,700&display=swap' rel='stylesheet'/>
</head><body>",
    "<header class='nav'><span class='brand'>", report_title_label(), "</span>",
    paste(nav_links, collapse = " "),
    "</header><main>",
    "<h1>HFCs</h1>",
    "<p class='meta'>Generated ", Sys.Date(), " · ", nrow(findings), " issues found · ",
    dplyr::n_distinct(findings$category), " categories</p>",
    about_html,
    "<section id='summary' class='card'><h2>Summary</h2>", summary_msg_html,
    "<h3>By category</h3>", summary_cards, "</section>",
    lastday_html,
    paste(mod_sections, collapse = "\n"),
    "<section id='all' class='card'><h2>All issues</h2>", all_tbl, all_enum_table_html, all_by_enum_html, "</section>",
    "<p class='note footer'>Field edits go in the shared <code>issue_tracking.xlsx</code> in your ",
    "OneDrive-synced folder (see <code>.claude/skills/hfc-agent-skill/config.json</code>)</p>",
    "</main>",
    REPORT_TABLE_JS,
    "</body></html>"
  )
  # The full report lives in detailed/; the parent file is the condensed
  # report - just the agent-drafted condensed message.
  lint_summary_messages(code_output_dir, roles$last_date %||% NA_character_, findings,
                        primary_known = "n_primary" %in% names(stats$M1$overall %||% list()))
  detailed_path <- detailed_report_path(html_path)
  dir.create(dirname(detailed_path), showWarnings = FALSE, recursive = TRUE)
  writeLines(html, detailed_path)
  sections_html <- render_condensed_sections(findings, stats, modules, roles, findings_col_labels)
  writeLines(condensed_report_html(read_condensed_message(code_output_dir), report_title_label(), sections_html), html_path)

  if (isTRUE(open) && !identical(Sys.getenv("CI"), "true") &&
      !identical(Sys.getenv("HFC_NO_OPEN"), "1")) {
    try(utils::browseURL(html_path), silent = TRUE)
  }
  normalizePath(html_path)
}

ensure_project_dirs <- function(code_output_dir) {
    hfc <- hfc_root(code_output_dir)
    for (d in c("config", "instruments", "outputs", "code")) {
        dir.create(file.path(hfc, d), recursive = TRUE, showWarnings = FALSE)
    }
    dir.create(file.path(hfc, "code", "checks"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(hfc, "code", "resolutions"), recursive = TRUE, showWarnings = FALSE)
}

# Module code -> its check_templates/ filename.
CHECK_TEMPLATE_FILES <- c(
    M1 = "M1_completion.R", M2 = "M2_duplicates.R", M3 = "M3_form_version.R",
    M4 = "M4_duration.R", M5 = "M5_date_issues.R", M6 = "M6_outliers.R",
    M7 = "M7_missingness.R", M8 = "M8_straightlining.R", M10 = "M10_gps.R",
    M11 = "M11_sumstats.R", M12 = "M12_balance.R", M13 = "M13_media.R",
    M14 = "M14_consent.R"
)

#' Copies each confirmed-on module's runnable check script into
#' hfc/code/checks/<name>.R, so running it standalone reproduces that
#' module's findings.
write_check_scripts <- function(code_output_dir, modules, skill_dir = NULL) {
    checks_dir <- hfc_path(code_output_dir, "code", "checks")
    dir.create(checks_dir, showWarnings = FALSE, recursive = TRUE)
    if (is.null(skill_dir) || is.na(skill_dir)) {
        stop("write_check_scripts() requires skill_dir — the caller must resolve it (see .resolve_skill() in each CLI script).")
    }
    tmpl_dir <- file.path(skill_dir, "assets", "check_templates")

    on_codes <- names(CHECK_TEMPLATE_FILES)[
        vapply(names(CHECK_TEMPLATE_FILES), function(m) isTRUE(modules[[m]]$on), logical(1))
    ]

    # Removes stale generated scripts for a module no longer confirmed on,
    # matched by their known filename - a renamed/repurposed file is never touched.
    off_codes <- setdiff(names(CHECK_TEMPLATE_FILES), on_codes)
    for (m in off_codes) {
        f <- file.path(checks_dir, CHECK_TEMPLATE_FILES[[m]])
        if (file.exists(f)) file.remove(f)
    }

    for (m in on_codes) {
        fname <- CHECK_TEMPLATE_FILES[[m]]
        tmpl <- file.path(tmpl_dir, fname)
        if (!file.exists(tmpl)) next
        lines <- readLines(tmpl, warn = FALSE)
        lines <- sub('skill <- "your/path/to/hfc-agent-skill/"',
        sprintf('skill <- "%s"', normalizePath(skill_dir)), lines, fixed = TRUE)
        lines <- sub('code_output_dir <- "your/path/to/hfc/output/"',
        sprintf('code_output_dir <- "%s"', normalizePath(code_output_dir)), lines, fixed = TRUE)
        writeLines(lines, file.path(checks_dir, fname))
    }

    # A one-call shortcut over whichever of the above are actually present —
    # written every build, regardless of which modules are on.
    main_tmpl <- file.path(tmpl_dir, "main.R")
    if (file.exists(main_tmpl)) {
        lines <- readLines(main_tmpl, warn = FALSE)
        lines <- sub('skill <- "your/path/to/hfc-agent-skill/"',
        sprintf('skill <- "%s"', normalizePath(skill_dir)), lines, fixed = TRUE)
        lines <- sub('code_output_dir <- "your/path/to/hfc/output/"',
        sprintf('code_output_dir <- "%s"', normalizePath(code_output_dir)), lines, fixed = TRUE)
        writeLines(lines, file.path(checks_dir, "main.R"))
    }
}

write_main_r <- function(code_output_dir, skill_dir = NULL) {
    dir.create(hfc_path(code_output_dir, "code"), showWarnings = FALSE, recursive = TRUE)
    dest <- hfc_path(code_output_dir, "code", "main.R")
    if (is.null(skill_dir) || is.na(skill_dir)) {
        stop("write_main_r() requires skill_dir — the caller must resolve it (see .resolve_skill() in each CLI script).")
    }
    tmpl <- file.path(skill_dir, "assets", "main.R")
    if (file.exists(tmpl)) {
        lines <- readLines(tmpl, warn = FALSE)
        lines <- sub('skill <- "your/path/to/hfc-agent-skill/"',
        sprintf('skill <- "%s"', normalizePath(skill_dir)), lines, fixed = TRUE)
        lines <- sub('code_output_dir <- "your/path/to/hfc/output/"',
        sprintf('code_output_dir <- "%s"', normalizePath(code_output_dir)), lines, fixed = TRUE)
        writeLines(lines, dest)
    } else {
        writeLines(c(
        "# HFC Agent Skill — two path globals",
        sprintf('skill <- "%s"', normalizePath(skill_dir)),
        sprintf('code_output_dir <- "%s"', normalizePath(code_output_dir)),
        'hfc <- file.path(code_output_dir, "hfc")',
        "# Rscript file.path(skill, \"scripts\", \"run_setup_build.R\")",
        "# Rscript file.path(skill, \"scripts\", \"apply_feedback.R\") \"clone\""
        ), dest)
    }
}

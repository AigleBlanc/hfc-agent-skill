# Runs M1-M14 checks given ds, roles, modules config.
# Returns list(findings = <tibble>, stats = <named list of data.frames per module>).
# Each module's check logic lives in its own check_mN(ds, roles, modules)
# function, returning list(findings=, stats=).

#' Resolves a per-row timezone: one global tz, or a per-row lookup via a
#' confirmed country column in multi-country mode.
resolve_row_timezone <- function(ds, roles) {
    n <- nrow(ds)
    if (identical(roles$country_mode, "multi") &&
        !is.null(roles$country_col) && !is.na(roles$country_col) &&
        roles$country_col %in% names(ds)) {
        map <- roles$country_timezone_map %||% list()
        vals <- as.character(ds[[roles$country_col]])
        tz <- vapply(vals, function(v) {
        t <- map[[v]]
        if (is.null(t) || !nzchar(t)) NA_character_ else t
        }, character(1), USE.NAMES = FALSE)
        return(tz)
    }
    rep(roles$timezone, n)
}

#' Extracts local hour-of-day and ISO weekday from a naive datetime vector,
#' honoring a possibly-different timezone per row.
local_daypart <- function(dt, tz_vec) {
    n <- length(dt)
    hr <- rep(NA_real_, n)
    wd <- rep(NA_integer_, n)
    tz_vec <- as.character(tz_vec)
    for (tz in unique(tz_vec[!is.na(tz_vec) & nzchar(tz_vec)])) {
        idx <- which(tz_vec == tz & !is.na(dt))
        if (!length(idx)) next
        sub <- tryCatch(lubridate::force_tz(dt[idx], tzone = tz), error = function(e) dt[idx])
        hr[idx] <- lubridate::hour(sub) + lubridate::minute(sub) / 60
        wd[idx] <- lubridate::wday(sub, week_start = 1)
    }
    list(hour = hr, wday = wd)
}

#' Same per-timezone approach as local_daypart(), also returning each row's
#' local calendar date and exact minute (for the daily start/end table).
local_date_hm <- function(dt, tz_vec) {
    n <- length(dt)
    date <- rep(NA_character_, n)
    hour <- rep(NA_integer_, n)
    minute <- rep(NA_integer_, n)
    tz_vec <- as.character(tz_vec)
    for (tz in unique(tz_vec[!is.na(tz_vec) & nzchar(tz_vec)])) {
        idx <- which(tz_vec == tz & !is.na(dt))
        if (!length(idx)) next
        sub <- tryCatch(lubridate::force_tz(dt[idx], tzone = tz), error = function(e) dt[idx])
        date[idx] <- as.character(as.Date(sub, tz = tz))
        hour[idx] <- lubridate::hour(sub)
        minute[idx] <- lubridate::minute(sub)
    }
    list(date = date, hour = hour, minute = minute)
}

#' Parse a start/end timestamp column into a naive POSIXct vector, trying a
#' couple of common SurveyCTO export formats.
parse_datetime_col <- function(x) {
    x <- as.character(x)
    dt <- suppressWarnings(lubridate::ymd_hms(x, quiet = TRUE))
    if (sum(!is.na(dt)) < 0.5 * length(x)) {
        dt <- suppressWarnings(lubridate::parse_date_time(
        x, orders = c("Ymd HMS", "mdy HMS", "Ymd HM", "mdy HM", "Ymd", "mdy"), quiet = TRUE
        ))
    }
    dt
}

#' Per-enumerator ID -> display-name lookup table. NULL when there's no
#' usable enumerator column.
enum_name_lookup <- function(ds, roles) {
  if (is.na(roles$enum) || !roles$enum %in% names(ds)) return(NULL)
  ename_vec <- resolve_unit_name(ds, roles$enum, roles$enum_name)
  tibble(.enum = as.character(ds[[roles$enum]]), .ename = ename_vec) %>%
    dplyr::filter(!is.na(.enum), nzchar(.enum)) %>%
    dplyr::group_by(.enum) %>%
    dplyr::summarise(.ename = dplyr::first(stats::na.omit(.ename), default = NA_character_), .groups = "drop")
}

#' Row-wise fraction of missing/blank cells across a set of columns.
row_missing_ratio <- function(ds, cols) {
    cols <- cols[cols %in% names(ds)]
    if (!length(cols)) return(rep(0, nrow(ds)))
    m <- vapply(cols, function(cn) {
        x <- ds[[cn]]
        if (is.character(x) || is.factor(x)) is.na(x) | !nzchar(as.character(x)) else is.na(x)
    }, logical(nrow(ds)))
    if (is.null(dim(m))) m <- matrix(m, nrow = nrow(ds))
    rowMeans(m)
}

#' TRUE where a value looks like a "yes/complete/positive" indicator.
is_complete_value <- function(x) {
    s <- tolower(trimws(as.character(x)))
    s %in% c("1", "yes", "y", "true", "complete", "completed", "full")
}

#' Full collection date range (min-max of roles$start), e.g. "2026-07-17 to
#' 2026-08-01" - a single bare date, un-ranged, when min == max. Shared by
#' M1's OVERALL table and M4's OVERALL/Last-Day duration tables, which both
#' need the exact same "Dates" value - one place computing it, so the two
#' can never drift apart.
date_range_label <- function(ds, roles) {
    if (is.null(ds) || is.null(roles$start) || is.na(roles$start) || !roles$start %in% names(ds)) return(NA_character_)
    d <- suppressWarnings(as.Date(as.character(ds[[roles$start]])))
    d <- d[!is.na(d)]
    if (!length(d)) return(NA_character_)
    lo <- format(min(d), "%Y-%m-%d")
    hi <- format(max(d), "%Y-%m-%d")
    if (identical(lo, hi)) lo else sprintf("%s to %s", lo, hi)
}

#' Count + percent-complete, overall or split by a grouping vector.
completion_summary <- function(complete_flag, group_vec = NULL) {
    if (is.null(group_vec)) {
        return(tibble::tibble(
        group = "Overall", n = length(complete_flag),
        n_complete = sum(complete_flag, na.rm = TRUE),
        pct_complete = round(100 * mean(complete_flag, na.rm = TRUE), 1)
        ))
    }
    tibble::tibble(group = as.character(group_vec), complete = complete_flag) %>%
        dplyr::filter(!is.na(group), nzchar(group)) %>%
        dplyr::group_by(group) %>%
        dplyr::summarise(
        n = dplyr::n(),
        n_complete = sum(complete, na.rm = TRUE),
        pct_complete = round(100 * mean(complete, na.rm = TRUE), 1),
        .groups = "drop"
        )
}

#' The row-level "is this row surveyed/complete" flag used to filter every
#' module besides M1 down to the M2-M14 "surveyed subset". "status" excludes
#' explicitly incomplete rows; "roster"/"primary_secondary" never remove rows
#' (every row in ds is a completed survey by construction under those
#' signals). Not to be confused with compute_completion_flag() below, which
#' this delegates to for the "primary_secondary"/no-signal cases and which
#' returns a list (sig, target_ds, complete_flag, ...) rather than a bare
#' logical vector.
compute_row_completed_flag <- function(ds, roles, modules = NULL) {
    sig <- roles$completion_primary_signal %||% NA_character_
    if (identical(sig, "roster")) {
        return(rep(TRUE, nrow(ds)))
    }
    if (identical(sig, "status")) {
        col <- roles$completion_status_col
        if (!is.null(col) && !is.na(col) && col %in% names(ds)) {
        complete_values <- roles$completion_status_complete_values %||% c("complete", "completed")
        return(tolower(trimws(as.character(ds[[col]]))) %in% tolower(complete_values))
        }
        return(rep(TRUE, nrow(ds)))
    }
    compute_completion_flag(ds, roles, modules %||% list())$complete_flag
}

#' Shared per-run setup: form-map resolution and the derived columns every
#' module relies on (.hfc_row, .hfc_id_display, .hfc_completed).
prepare_ds_for_checks <- function(ds, roles, code_output_dir = NULL, target_ds = NULL, modules = NULL) {
    suppressPackageStartupMessages({
        library(dplyr); library(lubridate); library(tibble)
    })
    form_map <- attr(ds, "hfc_form_map")
    if (is.null(form_map) && !is.null(code_output_dir)) {
        fp <- hfc_path(code_output_dir, "instruments", "form.xlsx")
        if (file.exists(fp) && exists("parse_form_relevance", mode = "function")) {
        form_map <- parse_form_relevance(fp)
        }
    }
    attr(ds, "hfc_form_map") <- form_map
    ds$.hfc_row <- seq_len(nrow(ds))
    ds$.hfc_id_display <- composite_id_string(ds, roles$entity_id, roles$entity_id_sep %||% " / ")
    ds$.hfc_completed <- compute_row_completed_flag(ds, roles, modules)
    attr(ds, "hfc_target_ds") <- target_ds
    ds
}

# ---- M1 Completion ---------------------------------------------------------
# Built around three possible completion signals (roles$completion_
# primary_signal): "status" (an explicit status column), "roster" (matched
# against a target/planned-sample file), "primary_secondary" (a sample-
# designation column, reports composition rather than a rate), or no signal
# (falls back to row-missingness). The separate low-completion-by-site
# finding below always operates on the actual surveyed data regardless.

#' Shared roster-join replacement summary, used by both M1's own stats/
#' findings and Balance Tables' Replacements table, so the two never join
#' the roster to the survey data two different ways. `group_col`/
#' `value_map` let a caller group by a different roster column and remap
#' its raw values to the survey data's own coding. Returns NULL when
#' prerequisites aren't met.
compute_replacement_roster_summary <- function(ds, roles, modules, target_ds, sig, complete_flag,
                                                group_col = NULL, value_map = NULL) {
    repl_status_col <- modules$M1$replacement_status_col %||% NA_character_
    repl_rank_col <- modules$M1$replacement_rank_col %||% NA_character_
    repl_group_col <- group_col %||% modules$M1$replacement_group_col %||% NA_character_
    if (is.null(target_ds) || is.na(repl_status_col) || !repl_status_col %in% names(target_ds) ||
        is.na(repl_rank_col) || !repl_rank_col %in% names(target_ds) ||
        is.na(repl_group_col) || !repl_group_col %in% names(target_ds) ||
        is.na(roles$entity_id[[1]] %||% NA_character_) || !roles$entity_id[[1]] %in% names(ds)) {
        return(NULL)
    }
    entity_col <- roles$entity_id[[1]]
    roster_key_col <- roles$completion_roster_key_col %||% entity_col

    ds_complete_flag <- if (identical(sig, "roster")) rep(TRUE, nrow(ds)) else complete_flag

    surveyed_key <- as.character(ds[[entity_col]])
    completed_key <- unique(surveyed_key[ds_complete_flag %in% TRUE])
    attempted_key <- unique(surveyed_key)

    primary_values <- tolower(trimws(as.character(modules$M1$replacement_primary_values %||% "primary")))
    is_primary <- tolower(trimws(as.character(target_ds[[repl_status_col]]))) %in% primary_values
    roster_key <- as.character(target_ds[[roster_key_col]])
    roster_grp <- as.character(target_ds[[repl_group_col]])
    if (!is.null(value_map) && length(value_map)) {
        roster_grp <- vapply(roster_grp, function(v) {
        mv <- value_map[[v]]
        if (is.null(mv)) v else as.character(mv)
        }, character(1), USE.NAMES = FALSE)
    }
    roster_rank <- suppressWarnings(as.numeric(target_ds[[repl_rank_col]]))

    roster_tbl <- tibble::tibble(key = roster_key, group = roster_grp, is_primary = is_primary, rank = roster_rank) %>%
        filter(!is.na(key), nzchar(key), !is.na(group), nzchar(group))
    if (!nrow(roster_tbl)) return(NULL)

    by_group_repl <- roster_tbl %>%
        group_by(group) %>%
        summarise(
        n_primary = sum(is_primary),
        n_primary_completed = sum(is_primary & key %in% completed_key),
        n_replaced = sum(!is_primary & key %in% completed_key),
        .groups = "drop"
        ) %>%
        filter(n_primary > 0)

    list(roster_tbl = roster_tbl, completed_key = completed_key, attempted_key = attempted_key,
        by_group_repl = by_group_repl)
}

#' Shared completion-flag computation, used by both check_m1() (Completion)
#' and render_balance_tables_body() (Balance Tables, scripts/lib/
#' balance_tables.R) — factored out so the two modules never compute "is
#' this row/entity completed" two different ways. See check_m1()'s own
#' header comment above for the four completion-signal semantics (gating/
#' status/roster/primary_secondary/no-signal fallback). Returns a list:
#' sig, target_ds, group_source_ds, complete_flag (row-aligned to `ds`
#' EXCEPT under "roster", where it's aligned to target_ds instead — see
#' check_m1()'s header comment), and (gating only) gate_cols/gate_pass/
#' gate_pass_fn, reused by check_m1()'s own reason-for-non-completion block.
compute_completion_flag <- function(ds, roles, modules) {
    sig <- roles$completion_primary_signal %||% NA_character_
    target_ds <- attr(ds, "hfc_target_ds")
    group_source_ds <- ds
    gate_cols <- character(); gate_pass <- list(); gate_pass_fn <- NULL

    if (identical(sig, "roster")) {
        # Every dead end here resets sig to NA (never leaves it as "roster"
        # with nothing resolved) — the dispatch chain below has no branch
        # for "roster" itself (that's handled entirely in this block), so
        # leaving sig stuck on "roster" with complete_flag never assigned
        # would fall through with nothing set at all, not just a worse
        # fallback. A real, confirmed case this guards: target_ds missing
        # its "hfc_target_ds" attribute on the `ds` passed to this function
        # (e.g. a caller like render_balance_tables_body() working from the
        # raw report-build `ds`, never routed through prepare_ds_for_checks()).
        if (is.null(target_ds) || is.na(roles$entity_id[[1]] %||% NA_character_)) {
        sig <- NA_character_
        } else {
        entity_col <- roles$entity_id[[1]]
        roster_key_col <- roles$completion_roster_key_col %||% entity_col
        if (roster_key_col %in% names(target_ds) && entity_col %in% names(ds)) {
            surveyed_keys <- as.character(ds[[entity_col]])
            target_keys <- as.character(target_ds[[roster_key_col]])
            complete_flag <- target_keys %in% surveyed_keys
            group_source_ds <- target_ds
        } else {
            sig <- NA_character_
        }
        }
    }
    if (identical(sig, "primary_secondary")) {
        ps_col <- roles$completion_primary_secondary_col
        primary_value <- roles$completion_primary_value %||% NA_character_
        complete_flag <- if (!is.na(ps_col) && ps_col %in% names(ds) && !is.na(primary_value)) {
        tolower(trimws(as.character(ds[[ps_col]]))) == tolower(primary_value)
        } else {
        rep(TRUE, nrow(ds))
        }
    } else if (identical(sig, "status")) {
        complete_flag <- ds$.hfc_completed
    } else if (identical(sig, "gating")) {
        # Complete only if every confirmed gate passes - a fail on any one
        # means the rest of the survey was never asked.
        gate_cols <- modules$M1$gate_cols %||% character()
        gate_cols <- gate_cols[!is.na(gate_cols) & gate_cols %in% names(ds)]
        gate_pass <- modules$M1$gate_pass_values %||% list()
        # A gate added to the form partway through collection is exempted
        # for submissions dated before it existed.
        gate_min_date <- modules$M1$gate_min_date %||% list()
        row_date <- if (!is.na(roles$start) && roles$start %in% names(ds)) {
        suppressWarnings(as.Date(as.character(ds[[roles$start]])))
        } else rep(as.Date(NA), nrow(ds))
        gate_pass_fn <- function(gc) {
        pv <- gate_pass[[gc]] %||% NA_character_
        # A blank/NA gate answer always means "did not pass," never NA.
        raw_pass <- if (is.na(pv)) {
            rep(TRUE, nrow(ds))
        } else {
            !is.na(ds[[gc]]) & tolower(trimws(as.character(ds[[gc]]))) == tolower(pv)
        }
        min_d <- gate_min_date[[gc]] %||% NA_character_
        if (!is.na(min_d)) {
            exempt <- !is.na(row_date) & row_date < as.Date(min_d)
            raw_pass <- raw_pass | exempt
        }
        raw_pass
        }
        if (length(gate_cols)) {
        pass_mat <- vapply(gate_cols, gate_pass_fn, logical(nrow(ds)))
        complete_flag <- apply(pass_mat, 1, all)
        # governing_gate: a later gate (typically consent) that overrides
        # an earlier gate's still-failed status, since it can legitimately
        # be revisited later in the interview.
        governing_gate <- modules$M1$governing_gate %||% NA_character_
        if (!is.na(governing_gate) && governing_gate %in% gate_cols) {
            complete_flag <- complete_flag | gate_pass_fn(governing_gate)
        }
        } else {
        complete_flag <- rep(TRUE, nrow(ds))
        }
    } else if (!identical(sig, "roster")) {
        completion_var <- modules$M1$completion_var %||% NA_character_
        complete_flag <- if (!is.na(completion_var) && completion_var %in% names(ds)) {
        is_complete_value(ds[[completion_var]])
        } else {
        row_missing_ratio(ds, setdiff(names(ds), c(".hfc_row", ".hfc_id_display", ".hfc_completed"))) <= 0.1
        }
    }

    list(sig = sig, target_ds = target_ds, group_source_ds = group_source_ds,
        complete_flag = complete_flag, gate_cols = gate_cols, gate_pass = gate_pass,
        gate_pass_fn = gate_pass_fn)
}

#' Row-level reason each `ds` row didn't complete (gating mode only): the
#' FIRST gate (in confirmed order) it failed, since nothing after it was ever
#' asked. Looks up a specific, substantive per-failing-VALUE reason from
#' modules$M1$gate_fail_reasons (agent-derived at setup from the question's
#' own label/choice list - e.g. "Household absent," not "Eligible") first,
#' trying the decoded value-label when the gate column is value-labelled and
#' it differs from the raw value, then the raw value itself; falls back to
#' the gate's own generic label (gate_labels) only when neither has a
#' specific entry. Returns a character vector aligned to `ds` (NA wherever no
#' gate failed, or the signal isn't gating). Shared by check_m1() and
#' build_completion_table() so the two never disagree.
compute_noncompletion_reason_vec <- function(ds, modules, cf) {
    reason_vec <- rep(NA_character_, nrow(ds))
    if (!identical(cf$sig, "gating") || !length(cf$gate_cols)) return(reason_vec)
    gate_labels <- modules$M1$gate_labels %||% list()
    gate_fail_reasons <- modules$M1$gate_fail_reasons %||% list()
    for (gc in cf$gate_cols) {
        pv <- cf$gate_pass[[gc]] %||% NA_character_
        if (is.na(pv)) next
        failed <- !cf$gate_pass_fn(gc)
        assign_idx <- is.na(reason_vec) & failed
        if (any(assign_idx)) {
        decoded <- decode_labelled_chr(ds[[gc]])
        raw <- as.character(ds[[gc]])
        gc_label <- gate_labels[[gc]] %||% gc
        gc_reasons <- gate_fail_reasons[[gc]] %||% list()
        v_dec <- decoded[assign_idx]
        v_raw <- raw[assign_idx]
        reason_vec[assign_idx] <- vapply(seq_along(v_dec), function(i) {
            r <- if (!is.na(v_dec[i]) && v_dec[i] %in% names(gc_reasons)) {
            gc_reasons[[v_dec[i]]]
            } else if (!is.na(v_raw[i]) && v_raw[i] %in% names(gc_reasons)) {
            gc_reasons[[v_raw[i]]]
            } else NA_character_
            if (!is.na(r) && nzchar(r)) r else gc_label
        }, character(1))
        }
    }
    reason_vec
}

#' Reason for each ROSTER row that was never attempted at all (no matching
#' row in `ds`), mapped from the roster's own status column via
#' modules$M1$nonstart_status_col/nonstart_reason_map; an unmapped status
#' becomes "Other". Character vector aligned to `target_ds` - NA for a row
#' that was attempted, has a blank status, or when no status column/roster is
#' configured.
compute_nonstart_reason_vec <- function(ds, roles, modules, target_ds) {
    if (is.null(target_ds)) return(character(0))
    out <- rep(NA_character_, nrow(target_ds))
    nonstart_col <- modules$M1$nonstart_status_col %||% NA_character_
    if (is.na(nonstart_col) || !nonstart_col %in% names(target_ds) ||
        is.na(roles$entity_id[[1]] %||% NA_character_) || !roles$entity_id[[1]] %in% names(ds)) {
        return(out)
    }
    entity_col <- roles$entity_id[[1]]
    roster_key_col <- roles$completion_roster_key_col %||% entity_col
    if (!roster_key_col %in% names(target_ds)) return(out)
    nonstart_map <- modules$M1$nonstart_reason_map %||% list()
    attempted_keys <- unique(as.character(ds[[entity_col]]))
    never_attempted <- !as.character(target_ds[[roster_key_col]]) %in% attempted_keys
    status_raw <- as.character(target_ds[[nonstart_col]])
    use <- never_attempted & !is.na(status_raw) & nzchar(status_raw)
    out[use] <- vapply(status_raw[use], function(v) {
        r <- if (v %in% names(nonstart_map)) nonstart_map[[v]] else NA_character_
        if (!is.null(r) && !is.na(r) && nzchar(r)) as.character(r) else "Other"
    }, character(1), USE.NAMES = FALSE)
    out
}

#' Respondent-level table behind the issue_tracking.xlsx "Completion" sheet.
#' With a roster (`target_ds`): the roster copied verbatim plus `submitted`,
#' `completed` (both 0/1) and `reason_no_completion`; without one: one row per
#' unique respondent ID in `ds`. Matches on roles$completion_roster_key_col
#' (roster side) and roles$entity_id[[1]] (survey side), as strings - the same
#' join M1 uses. A respondent is completed if ANY of their rows passes the
#' completion flag. `existing` is the prior Completion sheet; any column in it
#' that this function doesn't itself produce (a hand-added one) is carried
#' over by matching key. Returns a data.frame, or NULL when no respondent ID
#' column can be resolved.
build_completion_table <- function(ds, roles, modules, target_ds = NULL, existing = NULL) {
    entity_col <- roles$entity_id[[1]] %||% NA_character_
    if (is.na(entity_col) || !entity_col %in% names(ds)) return(NULL)
    new_cols <- c("submitted", "completed", "reason_no_completion")
    survey_key <- as.character(ds[[entity_col]])

    attr(ds, "hfc_target_ds") <- target_ds
    cf <- compute_completion_flag(ds, roles, modules)
    sig <- cf$sig
    row_reason <- compute_noncompletion_reason_vec(ds, modules, cf)

    # Row-level "complete" aligned to ds. Under "roster" the flag is aligned
    # to target_ds instead, and every surveyed row counts as complete.
    row_complete <- if (identical(sig, "roster") || length(cf$complete_flag) != nrow(ds)) {
        rep(TRUE, nrow(ds))
    } else cf$complete_flag %in% TRUE

    use_roster <- !is.null(target_ds) && nrow(target_ds) > 0 &&
        (roles$completion_roster_key_col %||% entity_col) %in% names(target_ds)
    if (use_roster) {
        key_col <- roles$completion_roster_key_col %||% entity_col
        out <- as.data.frame(target_ds, stringsAsFactors = FALSE, check.names = FALSE)
        out <- out[, setdiff(names(out), new_cols), drop = FALSE]
        key <- as.character(target_ds[[key_col]])
    } else {
        key <- unique(survey_key[!is.na(survey_key) & nzchar(survey_key)])
        out <- data.frame(key, stringsAsFactors = FALSE, check.names = FALSE)
        names(out) <- entity_col
    }

    submitted <- !is.na(key) & nzchar(key) & key %in% survey_key
    completed_keys <- unique(survey_key[row_complete & !is.na(survey_key)])
    completed <- submitted & key %in% completed_keys

    # First non-NA gate reason among a respondent's rows, if any.
    reason_by_key <- tapply(row_reason, survey_key, function(r) {
        r <- r[!is.na(r)]; if (length(r)) r[[1]] else NA_character_
    })
    reason <- rep("", length(key))
    sub_idx <- which(submitted & !completed)
    if (length(sub_idx)) {
        r <- as.character(reason_by_key[key[sub_idx]])
        r[is.na(r) | !nzchar(r)] <- "Incomplete"
        reason[sub_idx] <- r
    }
    not_sub <- which(!submitted)
    if (length(not_sub)) {
        ns <- if (use_roster) compute_nonstart_reason_vec(ds, roles, modules, target_ds)[not_sub] else rep(NA_character_, length(not_sub))
        ns[is.na(ns) | !nzchar(ns)] <- "Not submitted"
        reason[not_sub] <- ns
    }

    out$submitted <- as.integer(submitted)
    out$completed <- as.integer(completed)
    out$reason_no_completion <- reason

    # Carry over hand-added columns from the prior sheet, matched by key.
    if (!is.null(existing) && is.data.frame(existing) && nrow(existing)) {
        key_name <- if (use_roster) (roles$completion_roster_key_col %||% entity_col) else entity_col
        extra <- setdiff(names(existing), c(names(out), new_cols))
        if (length(extra) && key_name %in% names(existing)) {
        idx <- match(key, as.character(existing[[key_name]]))
        for (cn in extra) out[[cn]] <- as.character(existing[[cn]])[idx]
        }
    }
    out
}

check_m1 <- function(ds, roles, modules) {
    cf <- compute_completion_flag(ds, roles, modules)
    sig <- cf$sig; target_ds <- cf$target_ds; group_source_ds <- cf$group_source_ds
    complete_flag <- cf$complete_flag
    gate_cols <- cf$gate_cols; gate_pass <- cf$gate_pass; gate_pass_fn <- cf$gate_pass_fn

    # Computed early since BY GROUP below folds in its Target N/Primary
    # Completed/Progress columns.
    repl <- compute_replacement_roster_summary(ds, roles, modules, target_ds, sig, complete_flag)
    repl_group_col <- modules$M1$replacement_group_col %||% NA_character_

    stats_overall <- completion_summary(complete_flag) %>%
        dplyr::transmute(dates = date_range_label(ds, roles), n = n, n_complete = n_complete, pct_complete = pct_complete)
    # Blank rather than fabricated when no roster exists.
    stats_overall$primary_sample_completed <- if (!is.null(repl) && nrow(repl$by_group_repl)) {
        sum(repl$by_group_repl$n_primary_completed)
    } else NA_integer_

    group_vars <- modules$M1$group_vars %||% character()
    # Under "roster" mode, the roster's own strata column can carry a
    # different name than ds's - roles$completion_roster_group_map bridges
    # that mismatch.
    roster_group_map <- roles$completion_roster_group_map %||% list()
    resolve_group_var <- function(gv) {
        if (gv %in% names(group_source_ds)) return(gv)
        if (!identical(sig, "roster")) return(NA_character_)
        mapped <- roster_group_map[[gv]] %||% NA_character_
        if (!is.na(mapped) && mapped %in% names(group_source_ds)) mapped else NA_character_
    }
    by_group <- lapply(group_vars, function(gv) {
        gv_resolved <- resolve_group_var(gv)
        if (is.na(gv_resolved)) return(NULL)
        tbl <- completion_summary(complete_flag, group_source_ds[[gv_resolved]]) %>%
        mutate(group_var = gv, .before = 1) %>%
        rename(value = group) %>%
        select(-pct_complete)
        # Target N / Primary Completed / Progress: only meaningful for the
        # ONE group_var matching the roster's replacement_group_col - every
        # other grouping stays genuinely blank rather than guessed.
        if (!is.null(repl) && nrow(repl$by_group_repl) && !is.na(repl_group_col) && identical(gv, repl_group_col)) {
        joined <- repl$by_group_repl[match(tbl$value, repl$by_group_repl$group), ]
        tbl$primary_completed <- joined$n_primary_completed
        tbl$target_n <- joined$n_primary
        # Progress = ALL completed in this group / Target N, not just
        # Primary Completed - can read under 100% even with every
        # submission complete, if replacements haven't filled every slot.
        tbl$progress <- ifelse(
            !is.na(joined$n_primary) & joined$n_primary > 0,
            round(100 * tbl$n_complete / joined$n_primary, 1), NA_real_
        )
        } else {
        tbl$primary_completed <- NA_integer_
        tbl$target_n <- NA_integer_
        tbl$progress <- NA_real_
        }
        tbl
    })
    by_group <- by_group[!vapply(by_group, is.null, logical(1))]
    by_group_df <- if (length(by_group)) bind_rows(by_group) else tibble()
    by_enum_df <- if (isTRUE(modules$M1$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(group_source_ds)) {
        enum_disp <- resolve_display_vec(
        group_source_ds[[roles$enum]],
        resolve_unit_name(group_source_ds, roles$enum, roles$enum_name),
        roles$enumerator_display %||% "name"
        )
        completion_summary(complete_flag, enum_disp) %>% rename(enumerator = group) %>% arrange(desc(pct_complete))
    } else tibble()
    by_date_df <- if (isTRUE(modules$M1$by_date %||% TRUE) && !is.na(roles$start) && roles$start %in% names(group_source_ds)) {
        d <- suppressWarnings(as.Date(as.character(group_source_ds[[roles$start]])))
        completion_summary(complete_flag, as.character(d)) %>% rename(date = group) %>% arrange(desc(date))
    } else tibble()
    stats <- list(overall = stats_overall, by_group = by_group_df,
                    by_enumerator = by_enum_df, by_date = by_date_df)

    # Reasons for non-completion (gating mode only) — for each incomplete
    # respondent, the reason is the FIRST gate (in confirmed order) they
    # failed, since nothing after it was ever asked. Looks up a specific,
    # substantive per-failing-VALUE reason from modules$M1$gate_fail_reasons
    # (agent-derived at setup from the question's own label/choice list —
    # e.g. "Household absent," not "Eligible") first, trying the decoded
    # value-label when the gate column is value-labelled and it differs from
    # the raw value, then the raw value itself; falls back to the gate's own
    # generic label (gate_labels) only when neither has a specific entry —
    # an unanticipated raw value, or a config from before this field existed.
    by_reason_df <- tibble()
    if (identical(sig, "gating") && length(gate_cols)) {
        reason_vec <- compute_noncompletion_reason_vec(ds, modules, cf)
        reasons_present <- reason_vec[!complete_flag & !is.na(reason_vec)]
        if (length(reasons_present)) {
        by_reason_df <- tibble(reason = reasons_present) %>% count(reason, sort = TRUE, name = "count")
        }
    }

    # Non-start reasons: a roster entity never attempted at all has nothing
    # a gate could have failed on. Maps the roster's own status column
    # (beyond simple Primary/Replacement) onto a reason, so every non-
    # completed submission ends up with exactly one reason row.
    nonstart_reasons <- compute_nonstart_reason_vec(ds, roles, modules, target_ds)
    nonstart_reasons <- nonstart_reasons[!is.na(nonstart_reasons)]
    if (length(nonstart_reasons)) {
        by_reason_df <- bind_rows(
        by_reason_df,
        tibble(reason = nonstart_reasons) %>% count(reason, sort = TRUE, name = "count")
        ) %>%
        group_by(reason) %>% summarise(count = sum(count), .groups = "drop") %>% arrange(desc(count))
    }
    stats$by_reason <- by_reason_df

    findings <- empty_findings()

    # Day-by-day enumerator productivity against a user-stated daily
    # target: one finding per (enumerator, day) under target.
    daily_target <- suppressWarnings(as.numeric(modules$M1$daily_target_per_enum %||% NA_real_))
    if (!is.na(daily_target) && !is.na(roles$enum) && roles$enum %in% names(ds) &&
        !is.na(roles$start) && roles$start %in% names(ds)) {
        enum_raw <- as.character(ds[[roles$enum]])
        day_full <- suppressWarnings(as.Date(as.character(ds[[roles$start]])))
        grp_raw <- if (!is.na(roles$group) && roles$group %in% names(ds)) as.character(ds[[roles$group]]) else rep(NA_character_, nrow(ds))
        day_counts <- tibble::tibble(enum = enum_raw, day = day_full, grp = grp_raw) %>%
        filter(!is.na(enum), nzchar(enum), !is.na(day)) %>%
        count(enum, day, grp, name = "n") %>%
        distinct(enum, day, .keep_all = TRUE) %>%
        filter(n < daily_target)
        if (nrow(day_counts)) {
        enum_lookup <- enum_name_lookup(ds, roles)
        ename <- if (!is.null(enum_lookup)) enum_lookup$.ename[match(day_counts$enum, enum_lookup$.enum)] else NA_character_
        unit_df2 <- tibble::tibble(
            unit_id = day_counts$enum,
            unit_name = ename,
            .grp = day_counts$grp,
            .day = as.character(day_counts$day),
            .issue = sprintf("Below the daily target of %s: %d submitted", daily_target, day_counts$n),
            .value = sprintf("%d submitted (target %s)", day_counts$n, daily_target),
            .sortv = day_counts$n
        )
        day_findings <- mk_aggregate_finding(
            unit_df2, "low_completion_enum_day", "M1", "low_completion_enum_day", unit_df2$.issue,
            roles, unit_type = "enumerator", value_col = ".value", sort_value_col = ".sortv",
            date_col = ".day"
        )
        day_findings$group_id <- unit_df2$.grp
        day_findings$group_id[is.na(day_findings$group_id)] <- ""
        findings <- bind_rows(findings, day_findings)
        }
    }

    # `repl` was already computed above for BY GROUP.
    if (!is.null(repl)) {
        roster_tbl <- repl$roster_tbl
        completed_key <- repl$completed_key
        attempted_key <- repl$attempted_key
        by_group_repl <- repl$by_group_repl

        if (nrow(by_group_repl)) {
        # % Replaced = replacements completed / non-completed primary
        # submitted, not / Primary Targeted. Blank when every primary
        # already completed (denominator 0).
        by_repl_tbl <- by_group_repl %>%
            transmute(
            group, `Primary Targeted` = n_primary,
            `Primary Completed` = n_primary_completed, Replaced = n_replaced,
            `% Replaced` = ifelse(
                (n_primary - n_primary_completed) > 0,
                round(100 * n_replaced / (n_primary - n_primary_completed), 1),
                NA_real_
            )
            )
        names(by_repl_tbl)[1] <- roles$group_label %||% "Group"
        stats$by_replacement <- by_repl_tbl
        }

        # Validity: within each group's shared replacement queue (ordered
        # by rank), if the highest COMPLETED rank is K, every rank < K
        # must have a row in ds at all (attempted) — a rank with no row is
        # a genuine gap, skipped without being attempted.
        repl_tbl <- roster_tbl %>% filter(!is_primary, !is.na(rank))
        violations <- list()
        for (g in unique(repl_tbl$group)) {
            g_repl <- repl_tbl %>% filter(group == g) %>% arrange(rank)
            completed_ranks <- g_repl$rank[g_repl$key %in% completed_key]
            if (!length(completed_ranks)) next
            max_completed_rank <- max(completed_ranks)
            earlier <- g_repl %>% filter(rank < max_completed_rank)
            missing <- earlier %>% filter(!(key %in% attempted_key))
            if (nrow(missing)) {
            violations[[g]] <- tibble::tibble(
                group = g,
                .issue = sprintf(
                "Replacement rank %s was completed, but replacement rank%s %s in this %s %s no row in the submitted data at all",
                max_completed_rank,
                if (nrow(missing) > 1) "s" else "",
                paste(sort(missing$rank), collapse = ", "),
                tolower(roles$group_label %||% "group"),
                if (nrow(missing) > 1) "have" else "has"
                )
            )
            }
        }
        if (length(violations)) {
            viol_df <- bind_rows(violations)
            unit_df3 <- tibble::tibble(unit_id = viol_df$group, unit_name = NA_character_, .issue = viol_df$.issue)
            repl_findings <- mk_aggregate_finding(
            unit_df3, "replacement_sequence_gap", "M1", "replacement_sequence_gap", unit_df3$.issue,
            roles, unit_type = "group"
            )
            findings <- bind_rows(findings, repl_findings)
        }
    }

    list(findings = findings, stats = stats)
}

# ---- M2 Duplicates ----------------------------------------------------------
# One finding per duplicate group, not per duplicate row — Value lists
# every submission's timestamp so the detail isn't lost.
check_m2 <- function(ds, roles, modules) {
    findings <- empty_findings()
    idc <- modules$M2$id %||% roles$entity_id
    idc <- idc[!is.na(idc) & nzchar(as.character(idc)) & idc %in% names(ds)]
    # Extra disambiguating columns (e.g. round/wave) so an entity
    # legitimately surveyed more than once isn't flagged as a duplicate.
    extra <- modules$M2$extra_keys %||% character()
    extra <- extra[!is.na(extra) & nzchar(as.character(extra)) & extra %in% names(ds)]
    full_key <- c(idc, extra)
    time_col <- roles$start %||% NA_character_
    if (is.na(time_col) || !nzchar(time_col)) time_col <- roles$end %||% NA_character_
    parts <- list()
    if (length(full_key)) {
        dups <- ds %>%
        filter(if_all(all_of(full_key), ~ !is.na(.) & as.character(.) != "")) %>%
        group_by(across(all_of(full_key))) %>%
        filter(n() > 1) %>%
        ungroup()
        parts$m2 <- mk_duplicate_group_findings(
        dups, full_key, idc, "duplicates_id", "M2", "duplicates",
        sprintf("Duplicate rows sharing the same %s", paste(full_key, collapse = " + ")), roles, time_col
        )
        if (nrow(dups) == 0 && !is.na(roles$key) && roles$key %in% names(ds)) {
        dups2 <- ds %>%
            filter(!is.na(.data[[roles$key]]), as.character(.data[[roles$key]]) != "") %>%
            group_by(.data[[roles$key]]) %>%
            filter(n() > 1) %>%
            ungroup()
        parts$m2b <- mk_duplicate_group_findings(
            dups2, roles$key, idc, "duplicates_key", "M2", "duplicates",
            sprintf("Duplicate rows sharing the same %s", roles$key), roles, time_col
        )
        }
    }
    if (length(parts)) findings <- bind_rows(parts)
    list(findings = findings)
}

#' The configured expected date window for one version label. NA when no
#' window was ever confirmed for it.
expected_dates_for_version <- function(v, version_map) {
    for (vspec in version_map) {
        if (identical(vspec$version_label, v)) {
        lo <- as.character(vspec$date_start); hi <- as.character(vspec$date_end)
        return(if (identical(lo, hi)) lo else sprintf("%s to %s", lo, hi))
        }
    }
    NA_character_
}

# ---- M3 Form Version --------------------------------------------------------
check_m3 <- function(ds, roles, modules) {
    findings <- empty_findings()
    stats <- NULL
    version_col <- modules$M3$version_col %||% NA_character_
    version_map <- modules$M3$version_map %||% list()
    dcol <- roles$start
    if (!is.na(version_col) && version_col %in% names(ds)) {
        vc <- as.character(ds[[version_col]])
        if (!is.na(dcol) && dcol %in% names(ds)) {
        d <- suppressWarnings(as.Date(as.character(ds[[dcol]])))
        by_version <- tibble(version = vc, date = d) %>%
            filter(!is.na(version), nzchar(version)) %>%
            group_by(version) %>%
            summarise(n = n(), date_min = as.character(min(date, na.rm = TRUE)),
                    date_max = as.character(max(date, na.rm = TRUE)), .groups = "drop")
        by_version$expected_dates <- vapply(by_version$version, expected_dates_for_version,
                                            character(1), version_map = version_map)
        stats <- by_version
        }
        if (length(version_map) && !is.na(dcol) && dcol %in% names(ds)) {
        d <- suppressWarnings(as.Date(as.character(ds[[dcol]])))
        expected <- rep(NA_character_, nrow(ds))
        for (vspec in version_map) {
            d_start <- as.Date(vspec$date_start); d_end <- as.Date(vspec$date_end)
            idx <- which(!is.na(d) & d >= d_start & d <= d_end)
            expected[idx] <- vspec$version_label
        }
        mismatch <- !is.na(expected) & !is.na(vc) & nzchar(vc) & vc != expected
        if (any(mismatch)) {
            tmp <- ds[mismatch, , drop = FALSE]
            tmp$.v <- sprintf("recorded=%s expected=%s", vc[mismatch], expected[mismatch])
            findings <- mk_findings(
            tmp, "form_version_mismatch", "M3", "form_version_mismatch",
            "Recorded form version doesn't match the expected version for this date", roles, ".v",
            variable_name = version_col
            )
        }
        }
    } else if (length(version_map)) {
        rows <- lapply(version_map, function(v) {
        tibble(version = v$version_label, date_start = v$date_start, date_end = v$date_end)
        })
        stats <- bind_rows(rows)
    }
    list(findings = findings, stats = stats)
}

# ---- M4 Survey Duration ------------------------------------------------------
#' SD-outlier flags one duration vector (minutes). One-sided by default —
#' flagging unusually long durations is an explicit opt-in.
.m4_flag_outliers <- function(ds, dur, sd_rule, roles, variable_name, allow_long = FALSE) {
  ok <- is.finite(dur)
  parts <- list()
  mu <- mean(dur[ok]); sdv <- stats::sd(dur[ok])
  if (is.finite(mu) && is.finite(sdv) && sdv > 0) {
    long_flag <- allow_long & ok & dur > mu + sd_rule * sdv
    short_flag <- ok & dur < mu - sd_rule * sdv & dur > 0
    if (any(long_flag)) {
      tmp <- ds[long_flag, , drop = FALSE]; tmp$.v <- round1(dur[long_flag])
      parts$long <- mk_findings(
        tmp, "long_duration", "M4", "long_duration",
        sprintf("%s more than %s SD above the mean", variable_name, sd_rule), roles, ".v",
        variable_name = variable_name, sort_value_col = ".v"
      )
    }
    if (any(short_flag)) {
      tmp <- ds[short_flag, , drop = FALSE]; tmp$.v <- round1(dur[short_flag])
      parts$short <- mk_findings(
        tmp, "short_duration", "M4", "short_duration",
        sprintf("%s more than %s SD below the mean", variable_name, sd_rule), roles, ".v",
        variable_name = variable_name, sort_value_col = ".v"
      )
    }
  }
  if (length(parts)) bind_rows(parts) else empty_findings()
}

check_m4 <- function(ds, roles, modules) {
  findings <- empty_findings()
  stats <- NULL
  dc <- modules$M4$duration %||% roles$duration
  sd_rule <- modules$M4$sd_rule %||% 3
  allow_long <- isTRUE(modules$M4$advanced_long_flag$on)
  section_findings <- list()
  section_stats_extra <- list()

  # Section-level start/end pairs (SKILL.md A2, Keys & Hours window) — opted
  # into via modules$M4$section_pairs, a named list label -> list(start=,
  # end=) sourced from roles$section_time_pairs. Runs independently of the
  # overall duration column below: a survey can have section timing with or
  # without a single global duration field.
  section_pairs <- modules$M4$section_pairs %||% list()
  for (label in names(section_pairs)) {
    pr <- section_pairs[[label]]
    if (is.null(pr$start) || is.null(pr$end) ||
        !pr$start %in% names(ds) || !pr$end %in% names(ds)) next
    sec_dur <- as.numeric(difftime(
      parse_datetime_col(ds[[pr$end]]), parse_datetime_col(ds[[pr$start]]), units = "mins"
    ))
    finding_label <- paste0(label, " duration")
    section_stats_extra[[label]] <- sec_dur
    section_findings[[label]] <- .m4_flag_outliers(ds, sec_dur, sd_rule, roles, finding_label, allow_long)
  }

  stat_row <- function(label, vals) {
    tibble(level = label,
          min = round1(suppressWarnings(min(vals, na.rm = TRUE))),
          median = round1(stats::median(vals, na.rm = TRUE)),
          mean = round1(mean(vals, na.rm = TRUE)),
          max = round1(suppressWarnings(max(vals, na.rm = TRUE))),
          sd = round1(stats::sd(vals, na.rm = TRUE)),
          n = sum(is.finite(vals)))
  }

  if (!is.na(dc) && dc %in% names(ds)) {
    # Duration is always in seconds; converted to minutes once here.
    dur <- safe_num(ds[[dc]]) / 60
    ok <- is.finite(dur)
    stats_overall <- tibble(
      dates = date_range_label(ds, roles),
      min = round1(suppressWarnings(min(dur[ok], na.rm = TRUE))),
      median = round1(stats::median(dur[ok], na.rm = TRUE)),
      mean = round1(mean(dur[ok], na.rm = TRUE)),
      max = round1(suppressWarnings(max(dur[ok], na.rm = TRUE))),
      sd = round1(stats::sd(dur[ok], na.rm = TRUE)),
      n = sum(ok)
    )
    # Pre-computed per-section duration columns (e.g. introduction_duration).
    section_dur_cols <- grep("_duration$", setdiff(names(ds), dc), value = TRUE)
    section_map <- modules$M4$section_map %||% list()
    stats_section_precomputed <- if (length(section_dur_cols)) {
      bind_rows(lapply(section_dur_cols, function(cn) {
        label <- section_map[[cn]] %||% var_label(cn, roles)
        stat_row(label, safe_num(ds[[cn]]) / 60)
      }))
    } else tibble()
    stats_by_enum <- if (isTRUE(modules$M4$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(ds)) {
      enum_disp <- resolve_display_vec(
        ds[[roles$enum]], resolve_unit_name(ds, roles$enum, roles$enum_name),
        roles$enumerator_display %||% "name"
      )
      ds %>% mutate(.dur = dur, .enum_disp = enum_disp) %>% filter(is.finite(.dur)) %>%
        group_by(enumerator = .enum_disp) %>%
        summarise(min = round1(min(.dur)), median = round1(stats::median(.dur)), mean = round1(mean(.dur)),
                  max = round1(max(.dur)), sd = round1(stats::sd(.dur)), n = n(),
                  .groups = "drop")
    } else tibble()

    section_findings[["__overall__"]] <- .m4_flag_outliers(ds, dur, sd_rule, roles, dc, allow_long)
    stats <- list(overall = stats_overall, by_enumerator = stats_by_enum)
  } else {
    stats_section_precomputed <- tibble()
    stats <- list(overall = tibble(), by_enumerator = tibble())
  }

  stats_section_pairs <- if (length(section_stats_extra)) {
    bind_rows(lapply(names(section_stats_extra), function(lbl) stat_row(lbl, section_stats_extra[[lbl]])))
  } else tibble()
  stats$by_section <- bind_rows(stats_section_precomputed, stats_section_pairs)

  # Daily earliest/latest start/end times - always present, independent of
  # whether a duration column is configured at all.
  if (!is.na(roles$start) && roles$start %in% names(ds)) {
    row_tz <- resolve_row_timezone(ds, roles)
    fmt_hm <- function(hour, minute) {
      tolower(format(ISOdatetime(2000, 1, 1, hour, minute, 0, tz = "UTC"), "%I:%M %p"))
    }
    start_parts <- local_date_hm(parse_datetime_col(ds[[roles$start]]), row_tz)
    has_end <- !is.na(roles$end) && roles$end %in% names(ds)
    end_parts <- if (has_end) {
      local_date_hm(parse_datetime_col(ds[[roles$end]]), row_tz)
    } else {
      list(date = rep(NA_character_, nrow(ds)), hour = rep(NA_integer_, nrow(ds)), minute = rep(NA_integer_, nrow(ds)))
    }
    day_tbl <- tibble(
      day = start_parts$date, s_hour = start_parts$hour, s_min = start_parts$minute,
      e_hour = end_parts$hour, e_min = end_parts$minute
    ) %>% filter(!is.na(day))
    if (nrow(day_tbl)) {
      by_day_time <- day_tbl %>%
        mutate(.s = s_hour * 60 + s_min, .e = e_hour * 60 + e_min) %>%
        group_by(day) %>%
        summarise(
          `Earliest Start` = fmt_hm(s_hour[which.min(.s)], s_min[which.min(.s)]),
          `Latest Start` = fmt_hm(s_hour[which.max(.s)], s_min[which.max(.s)]),
          `Earliest End` = if (all(is.na(.e))) NA_character_ else fmt_hm(e_hour[which.min(.e)], e_min[which.min(.e)]),
          `Latest End` = if (all(is.na(.e))) NA_character_ else fmt_hm(e_hour[which.max(.e)], e_min[which.max(.e)]),
          .groups = "drop"
        ) %>%
        arrange(day) %>%
        rename(Date = day)
      stats$by_day_times <- by_day_time
    }
  }

  if (length(section_findings)) findings <- bind_rows(section_findings)
  list(findings = findings, stats = stats)
}

# ---- M5 Irregular Timing (tz-aware) -----------------------------------------
check_m5 <- function(ds, roles, modules) {
  findings <- empty_findings()
  st <- roles$start
  if (!is.na(st) && st %in% names(ds)) {
    dt <- parse_datetime_col(ds[[st]])
    row_tz <- resolve_row_timezone(ds, roles)
    dp <- local_daypart(dt, row_tz)
    evening_hour <- modules$M5$evening_hour %||% 19
    morning_hour <- modules$M5$morning_hour %||% 7
    flag_weekend <- isTRUE(modules$M5$flag_weekend %||% TRUE)
    is_weekend <- flag_weekend & dp$wday %in% c(6, 7)
    is_offhours <- dp$hour >= evening_hour | dp$hour < morning_hour
    flag <- (is_weekend | is_offhours) & !is.na(dt)
    if (any(flag)) {
      tmp <- ds[flag, , drop = FALSE]
      tmp$.v <- format(dt[flag], "%Y-%m-%d %H:%M")
      hrs_window <- sprintf("%02d:00-%02d:00", morning_hour, evening_hour)
      reason <- ifelse(
        is_weekend[flag] & is_offhours[flag],
        sprintf("weekend and outside %s local time", hrs_window),
        ifelse(is_weekend[flag], "on a weekend",
               sprintf("outside %s local time", hrs_window))
      )
      tmp$.issue <- sprintf("Interview conducted %s", reason)
      off_dist <- ifelse(dp$hour[flag] >= evening_hour, dp$hour[flag] - evening_hour,
                   ifelse(dp$hour[flag] < morning_hour, morning_hour - dp$hour[flag], 0))
      tmp$.sortv <- off_dist + ifelse(is_weekend[flag], 1, 0)
      findings <- mk_findings(
        tmp, "irregular_time", "M5", "irregular_time",
        tmp$.issue, roles, ".v", sort_value_col = ".sortv"
      )
    }
  }
  list(findings = findings)
}

# ---- M6 Numeric Outliers (up to 10 vars, clean two-sided N-SD, or a fixed
# absolute range per variable) -------------------------------------------
check_m6 <- function(ds, roles, modules) {
  findings <- empty_findings()
  vars <- modules$M6$vars %||% character()
  vars <- vars[!is.na(vars) & vars %in% names(ds)]
  sd_rule <- modules$M6$sd_rule %||% 3
  # "sd" (default): unchanged mean±sd_rule*SD, relative to this project's
  # own data. "fixed": a fixed absolute range per variable
  # (fixed_thresholds[[vc]] = list(low=, high=), one-sided when either bound
  # is NA) — for surveys where a relative rule doesn't make sense (e.g. a
  # known plausible age/score range independent of what this sample
  # happens to contain). A variable with outlier_mode == "fixed" but no
  # configured fixed_thresholds entry falls back to the SD rule rather than
  # silently skipping outlier detection for it.
  outlier_mode <- modules$M6$outlier_mode %||% "sd"
  fixed_thresholds <- modules$M6$fixed_thresholds %||% list()
  parts <- list()
  for (vc in vars) {
    v <- safe_num(ds[[vc]])
    ok <- is.finite(v)
    if (sum(ok) < 30) next
    use_fixed <- identical(outlier_mode, "fixed") && !is.null(fixed_thresholds[[vc]])
    if (use_fixed) {
      low <- suppressWarnings(as.numeric(fixed_thresholds[[vc]]$low %||% NA_real_))
      high <- suppressWarnings(as.numeric(fixed_thresholds[[vc]]$high %||% NA_real_))
      if (is.na(low) && is.na(high)) next
      flag <- ok & ((!is.na(low) & v < low) | (!is.na(high) & v > high))
      if (!any(flag)) next
      tmp <- ds[flag, , drop = FALSE]
      tmp$.v <- round1(v[flag])
      below <- !is.na(low) & v[flag] < low
      tmp$.sortv <- ifelse(below, low - v[flag], v[flag] - high)
      tmp$.direction <- ifelse(below, "less", "more")
      bound_txt <- if (!is.na(low) && !is.na(high)) sprintf("outside the fixed range %s-%s", round1(low), round1(high)) else
        if (!is.na(low)) sprintf("below the fixed minimum of %s", round1(low)) else sprintf("above the fixed maximum of %s", round1(high))
    } else {
      mu <- mean(v[ok]); sdv <- stats::sd(v[ok])
      if (!is.finite(sdv) || sdv <= 0) next
      flag <- ok & abs(v - mu) > sd_rule * sdv
      if (!any(flag)) next
      tmp <- ds[flag, , drop = FALSE]
      tmp$.v <- round1(v[flag])
      tmp$.sortv <- abs(v[flag] - mu) / sdv
      tmp$.direction <- ifelse(v[flag] > mu, "more", "less")
      bound_txt <- sprintf("%s than %s SD from the mean", tmp$.direction, sd_rule)
    }
    catg <- if (identical(vc, roles$age) || grepl("age", vc, ignore.case = TRUE)) "age_outlier" else "numeric_outlier"
    tmp <- utils::head(tmp, 200)
    label <- sprintf("Outlier value for %s; the value is %s", var_label(vc, roles), bound_txt)
    parts[[vc]] <- mk_findings(
      tmp, sprintf("outlier_%s", vc), "M6", catg, label, roles, ".v",
      variable_name = vc, sort_value_col = ".sortv"
    )
  }
  if (length(parts)) findings <- bind_rows(parts)
  list(findings = findings)
}

# ---- M7 Missingness ----------------------------------------------------------
check_m7 <- function(ds, roles, modules) {
  vars <- modules$M7$vars %||% character()
  vars <- vars[!is.na(vars) & vars %in% names(ds)]
  sentinel <- modules$M7$sentinel_codes %||% character()
  sentinel_is_map <- is.list(sentinel) && !is.null(names(sentinel))
  # `has_enum` gates only the opt-in advanced_enum_flag finding - no
  # descriptive by-enumerator stats table exists.
  has_enum <- !is.na(roles$enum) && roles$enum %in% names(ds)
  # var_issue_threshold gates the OVERALL table (95% by default).
  # enum_pool_threshold/enum_pct_threshold configure the opt-in advanced
  # flag: only the worst variables are eligible, and an enumerator is
  # flagged if their own missingness clears the personal threshold.
  var_issue_threshold <- modules$M7$var_issue_threshold %||% 0.95
  enum_pool_threshold <- modules$M7$enum_pool_threshold %||% 0.9
  enum_pct_threshold <- modules$M7$enum_pct_threshold %||% 0.5
  form_map <- attr(ds, "hfc_form_map")
  enum_lookup <- if (has_enum) enum_name_lookup(ds, roles) else NULL
  by_var <- list(); enum_flags <- list()
  for (vc in vars) {
    codes <- if (sentinel_is_map) sentinel[[vc]] %||% character() else sentinel
    x <- ds[[vc]]
    miss <- is.na(x) | as.character(x) %in% as.character(codes)

    # A row correctly routed around this question never counts toward
    # missingness - dropped from both the numerator and denominator.
    applicable <- rep(TRUE, nrow(ds))
    if (!is.null(form_map) && nrow(form_map) > 0 && vc %in% form_map$name &&
        exists("row_is_relevant", mode = "function")) {
      rel <- form_map$relevant[match(vc, form_map$name)]
      if (!is.na(rel) && nzchar(rel)) applicable <- row_is_relevant(ds, rel)
    }
    miss[!applicable] <- FALSE
    n_applicable <- sum(applicable)
    pct_missing <- if (n_applicable > 0) round(100 * sum(miss) / n_applicable, 1) else NA_real_

    if (is.na(pct_missing) || pct_missing <= var_issue_threshold * 100) next
    by_var[[vc]] <- tibble(variable = var_label(vc, roles), pct_missing = pct_missing,
                            n_missing = sum(miss), n = n_applicable)

    if (has_enum) {
      by_e <- tibble(enumerator = as.character(ds[[roles$enum]]), miss = miss, applicable = applicable) %>%
        filter(!is.na(enumerator), nzchar(enumerator), applicable) %>%
        group_by(enumerator) %>%
        summarise(pct_missing = round(100 * mean(miss), 1), n = n(), .groups = "drop") %>%
        mutate(variable = var_label(vc, roles))

      # Eligible for enumerator-level flagging once population missingness
      # clears the (higher) pool threshold.
      if (pct_missing >= enum_pool_threshold * 100) {
        hi <- by_e %>% filter(pct_missing >= enum_pct_threshold * 100)
        if (nrow(hi)) enum_flags[[vc]] <- hi %>% mutate(variable = vc)
      }
    }
  }

  # Missingness is descriptive-only by default; the opt-in advanced flag
  # produces one finding per enumerator (not per enumerator-variable pair),
  # listing every flagged variable together.
  findings <- empty_findings()
  if (isTRUE(modules$M7$advanced_enum_flag$on) && length(enum_flags)) {
    all_flags <- bind_rows(enum_flags)
    by_enum_agg <- all_flags %>%
      group_by(enumerator) %>%
      summarise(
        vars = paste(variable, collapse = ", "),
        pct_vals = paste(sprintf("%s%%", pct_missing), collapse = " & "),
        worst_pct = max(pct_missing),
        .groups = "drop"
      )
    ename <- if (!is.null(enum_lookup)) enum_lookup$.ename[match(by_enum_agg$enumerator, enum_lookup$.enum)] else NA_character_
    unit_df <- tibble::tibble(
      unit_id = by_enum_agg$enumerator,
      unit_name = ename,
      .issue = sprintf("Enumerator's missingness is %.0f%%+ on %s", enum_pct_threshold * 100, by_enum_agg$vars),
      .value_display = by_enum_agg$pct_vals,
      .sort = by_enum_agg$worst_pct
    )
    findings <- mk_aggregate_finding(
      unit_df, "high_missing_enum", "M7", "high_missingness", unit_df$.issue,
      roles, unit_type = "enumerator", value_col = ".value_display", sort_value_col = ".sort"
    )
  }

  stats <- list(
    by_variable = if (length(by_var)) bind_rows(by_var) else tibble()
  )
  list(findings = findings, stats = stats)
}

# ---- M10 GPS Map ---------------------------------------------------------------
# Pure visualization by default (report_sections.json: "no distance
# threshold, no flagged points, no findings table") — the map itself is
# rendered separately by render_gps_map_body() (build_outputs.R) from ds
# directly, not from this function's findings. The median-reference
# distance-outlier logic below is tested and kept available as an opt-in
# advanced flag (modules$M10$advanced_distance_flag$on, default FALSE)
# rather than deleted outright, same posture as M7 Missingness's
# advanced_enum_flag.
check_m10 <- function(ds, roles, modules) {
  findings <- empty_findings()
  if (!isTRUE(modules$M10$advanced_distance_flag$on)) return(list(findings = findings))
  xc <- modules$M10$x %||% roles$x
  yc <- modules$M10$y %||% roles$y
  thr <- modules$M10$advanced_distance_flag$threshold_m %||% 300
  grp <- roles$group
  if (!is.na(xc) && !is.na(yc) && !is.na(grp) && all(c(xc, yc, grp) %in% names(ds))) {
    tmp <- ds %>%
      mutate(x = safe_num(.data[[xc]]), y = safe_num(.data[[yc]]), grp = .data[[grp]]) %>%
      filter(is.finite(x), is.finite(y), !is.na(grp))
    ref <- tmp %>% group_by(grp) %>% summarise(rx = median(x), ry = median(y), .groups = "drop")
    tmp <- tmp %>% left_join(ref, by = "grp") %>%
      mutate(dist_m = sqrt((x - rx)^2 + (y - ry)^2))
    if (median(abs(tmp$x), na.rm = TRUE) < 180 && median(abs(tmp$y), na.rm = TRUE) < 90) {
      if (requireNamespace("geosphere", quietly = TRUE)) {
        tmp$dist_m <- geosphere::distHaversine(cbind(tmp$x, tmp$y), cbind(tmp$rx, tmp$ry))
      }
    }
    flagged <- tmp %>% filter(is.finite(dist_m), dist_m > thr)
    if (nrow(flagged) > 0) {
      flagged$.v <- as.character(round1(flagged$dist_m))
      findings <- mk_findings(
        flagged, "gps_distance", "M10", "gps_distance",
        sprintf("Distance between reference and survey coordinates is %.1f meters", round1(flagged$dist_m)),
        roles, ".v", sort_value_col = "dist_m"
      )
    }
  }
  list(findings = findings)
}

# ---- M8 Straightlining -------------------------------------------------------
check_m8 <- function(ds, roles, modules) {
  ordinal_vars <- modules$M8$ordinal_vars %||% character()
  ordinal_vars <- ordinal_vars[!is.na(ordinal_vars) & ordinal_vars %in% names(ds)]
  enum_thr <- modules$M8$enum_threshold_pct %||% 1.0
  survey_thr <- modules$M8$survey_threshold_pct %||% 0.9
  # Skip a day with 2 or fewer completed surveys for that enumerator - not
  # enough to establish a pattern.
  min_n_per_enum_day <- 3L
  parts <- list()

  date_vec <- if (!is.na(roles$start) && roles$start %in% names(ds)) {
    as.character(suppressWarnings(as.Date(as.character(ds[[roles$start]]))))
  } else {
    rep(NA_character_, nrow(ds))
  }

  if (length(ordinal_vars) && !is.na(roles$enum) && roles$enum %in% names(ds)) {
    enum_vec <- as.character(ds[[roles$enum]])
    enum_lookup <- enum_name_lookup(ds, roles)
    flagged_rows <- list()
    for (vc in ordinal_vars) {
      v <- decode_labelled_chr(ds[[vc]])
      ok <- !is.na(v) & nzchar(v) & !is.na(enum_vec) & nzchar(enum_vec) & !is.na(date_vec)
      if (!any(ok)) next
      tab <- tibble(enum = enum_vec[ok], date = date_vec[ok], v = v[ok]) %>%
        group_by(enum, date) %>%
        summarise(
          n = n(),
          top_val = names(sort(table(v), decreasing = TRUE))[1],
          top_share = max(table(v)) / n(),
          .groups = "drop"
        ) %>%
        filter(n >= min_n_per_enum_day, top_share >= enum_thr)
      if (!nrow(tab)) next
      flagged_rows[[vc]] <- tab %>% mutate(variable = var_label(vc, roles))
    }
    # One row per (enumerator, day), not one per (enumerator, day, variable).
    if (length(flagged_rows)) {
      by_enum <- bind_rows(flagged_rows) %>%
        group_by(enum, date) %>%
        summarise(
          vars = paste(variable, collapse = ", "),
          top_vals = paste(top_val, collapse = " & "),
          worst_share = max(top_share),
          .groups = "drop"
        )
      ename <- if (!is.null(enum_lookup)) enum_lookup$.ename[match(by_enum$enum, enum_lookup$.enum)] else NA_character_
      unit_df <- tibble::tibble(
        unit_id = by_enum$enum,
        unit_name = ename,
        .date = by_enum$date,
        .issue = sprintf("Enumerator gave the same answer on %s in %.0f%%+ of their surveys that day", by_enum$vars, enum_thr * 100),
        .value_display = by_enum$top_vals,
        .share_sort = by_enum$worst_share
      )
      parts$enum <- mk_aggregate_finding(
        unit_df, "straightlining_enum", "M8", "straightlining_enum", unit_df$.issue,
        roles, unit_type = "enumerator", value_col = ".value_display", sort_value_col = ".share_sort",
        date_col = ".date"
      )
    }
  }

  if (length(ordinal_vars) >= 2) {
    sub_mat <- as.data.frame(lapply(ds[ordinal_vars], as.character), stringsAsFactors = FALSE)
    share <- apply(sub_mat, 1, function(row) {
      row <- row[!is.na(row) & nzchar(row)]
      if (length(row) < 2) return(0)
      max(table(row)) / length(row)
    })
    flag <- share >= survey_thr
    if (any(flag)) {
      tmp <- ds[flag, , drop = FALSE]
      tmp$.sortv <- share[flag]
      tmp$.v <- sprintf("%s%%", round1(share[flag] * 100))
      parts$survey <- mk_findings(
        tmp, "straightlining_survey", "M8", "straightlining_survey",
        sprintf("%.0f%%+ of this submission's ordinal answers are identical", survey_thr * 100),
        roles, ".v", sort_value_col = ".sortv"
      )
    }
  }
  findings <- if (length(parts)) bind_rows(parts) else empty_findings()
  list(findings = findings)
}

# ---- M11 Summary Statistics (descriptive only, never produces findings) ----
# Returns "Overall" plus one table per enumerator (same shape, but "Overall
# Mean" in place of Median).
check_m11 <- function(ds, roles, modules) {
  vars <- modules$M11$vars %||% character()
  vars <- vars[!is.na(vars) & vars %in% names(ds)]
  duration_col <- modules$M4$duration %||% roles$duration

  mk_table <- function(sub_ds) {
    rows <- lapply(vars, function(vc) {
      v <- safe_num(sub_ds[[vc]])
      if (!is.na(duration_col) && identical(vc, duration_col)) v <- v / 60
      ok <- is.finite(v)
      tibble(Variable = var_label(vc, roles), Min = round1(suppressWarnings(min(v[ok]))),
            Median = round1(stats::median(v[ok])), Mean = round1(mean(v[ok])),
            Max = round1(suppressWarnings(max(v[ok]))), SD = round1(stats::sd(v[ok])),
            Missing = sum(!ok), Obs = sum(ok))
    })
    if (length(rows)) bind_rows(rows) else tibble()
  }

  overall_tbl <- mk_table(ds)
  stats <- list(Overall = overall_tbl)

  by_enum <- isTRUE(modules$M11$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(ds)
  if (by_enum && length(vars)) {
    # Overall Mean: the same variable's mean across the entire dataset,
    # keyed by Variable's display label - never recomputed per enumerator.
    overall_mean_lookup <- stats::setNames(overall_tbl$Mean, overall_tbl$Variable)
    enum_vals <- as.character(ds[[roles$enum]])
    enum_names <- resolve_unit_name(ds, roles$enum, roles$enum_name)
    show_name <- identical(roles$enumerator_display %||% "name", "name")
    for (ev in sort(unique(enum_vals[!is.na(enum_vals) & nzchar(enum_vals)]))) {
      idx <- which(enum_vals == ev)
      label <- if (show_name) {
        nm <- unique(enum_names[idx]); nm <- nm[!is.na(nm) & nzchar(nm) & nm != ev]
        if (length(nm)) sprintf("%s (%s)", nm[[1]], ev) else ev
      } else ev
      tbl <- mk_table(ds[idx, , drop = FALSE])
      tbl$`Overall Mean` <- unname(overall_mean_lookup[tbl$Variable])
      stats[[label]] <- tbl[, c("Variable", "Overall Mean", "Mean", "SD", "Min", "Max", "Missing", "Obs")]
    }
  }
  list(stats = stats)
}

# ---- M14 Consent / assent / audio flags -------------------------------------
check_m14 <- function(ds, roles, modules) {
    form_map <- attr(ds, "hfc_form_map")
    flag_miss <- function(col, check_id, category, issue) {
        if (is.na(col) || !col %in% names(ds)) return(NULL)
        miss <- ds %>% filter(is.na(.data[[col]]) |
                                as.character(.data[[col]]) %in% c("", "0", "No", "no"))
        if (exists("filter_expected_skips", mode = "function") && !is.null(form_map)) {
        miss <- filter_expected_skips(miss, ds, col, form_map)
        }
        # If every surveyed row is flagged, this is one structural problem,
        # not a per-row gap - one dataset-level finding instead.
        if (nrow(ds) > 0 && nrow(miss) == nrow(ds)) {
        return(tibble(
            finding_id = paste0("m14:column_empty:", col),
            check_id = paste0(check_id, "_column_empty"),
            check_module = "M14",
            category = paste0(category, "_column_empty"),
            issue = sprintf(
            "%s. Every one of %d surveyed rows is missing/0/No on column '%s'. Likely the wrong column was detected, or this field was never actually captured, not a per-row gap.",
            issue, nrow(ds), var_label(col, roles)
            ),
            submission_id = "", group_id = "", enumerator = "", start_date = "", end_date = "",
            key = "", value = "", variable = col, entity_name = "", group_name = "", enumerator_name = "",
            sort_value = NA_real_
        ))
        }
        mk_findings(miss, check_id, "M14", category, sprintf("%s (column '%s')", issue, var_label(col, roles)), roles)
    }
    parts <- list()
    if (!is.na(roles$assent)) {
        parts$a <- flag_miss(roles$assent, "missing_assent", "assent",
                            "Missing, 0, or No assent flag")
    }
    if (!is.na(roles$consent)) {
        parts$c <- flag_miss(roles$consent, "missing_consent", "consent",
                            "Missing, 0, or No consent flag")
    }
    audio_flag <- modules$M14$audio %||% roles$audio_flag
    media_files <- unique(c(roles$audio_file_cols %||% character(),
                            roles$image_file_cols %||% character()))
    if (!is.na(audio_flag) && audio_flag %in% names(ds) && !audio_flag %in% media_files) {
        parts$aud <- flag_miss(audio_flag, "missing_audio_flag", "audio",
                                "Missing, 0, or No audio consent flag")
    }
    parts <- Filter(Negate(is.null), parts)
    findings <- if (length(parts)) bind_rows(parts) else empty_findings()
    list(findings = findings)
}

run_check_modules <- function(ds, roles, modules, code_output_dir = NULL, target_ds = NULL) {
  ds_full <- prepare_ds_for_checks(ds, roles, code_output_dir, target_ds = target_ds, modules = modules)
  ds_filtered <- if (any(!ds_full$.hfc_completed)) {
    filtered <- ds_full[ds_full$.hfc_completed, , drop = FALSE]
    attr(filtered, "hfc_form_map") <- attr(ds_full, "hfc_form_map")
    filtered
  } else {
    ds_full
  }
  # M1 needs the full, unfiltered dataset to compute completion rates;
  # every other module sees the completed/surveyed subset only.
  ds_for_module <- function(mod_code) ds_for_module_selection(ds_full, mod_code, modules)
  ds <- ds_filtered
  findings_list <- list()
  stats_list <- list()

  if (isTRUE(modules$M1$on)) {
    tryCatch({
      r <- check_m1(ds_for_module("M1"), roles, modules)
      findings_list$m1 <- r$findings
      stats_list$M1 <- r$stats
    }, error = function(e) message("M1: ", e$message))
  }

  if (isTRUE(modules$M2$on)) {
    tryCatch({
      findings_list$m2 <- check_m2(ds_for_module("M2"), roles, modules)$findings
    }, error = function(e) message("M2: ", e$message))
  }

  if (isTRUE(modules$M3$on)) {
    tryCatch({
      r <- check_m3(ds_for_module("M3"), roles, modules)
      findings_list$m3 <- r$findings
      stats_list$M3 <- r$stats
    }, error = function(e) message("M3: ", e$message))
  }

  if (isTRUE(modules$M4$on)) {
    tryCatch({
      r <- check_m4(ds_for_module("M4"), roles, modules)
      findings_list$m4 <- r$findings
      stats_list$M4 <- r$stats
    }, error = function(e) message("M4: ", e$message))
  }

  if (isTRUE(modules$M5$on)) {
    tryCatch({
      findings_list$m5 <- check_m5(ds_for_module("M5"), roles, modules)$findings
    }, error = function(e) message("M5: ", e$message))
  }

  if (isTRUE(modules$M6$on)) {
    tryCatch({
      findings_list$m6 <- check_m6(ds_for_module("M6"), roles, modules)$findings
    }, error = function(e) message("M6: ", e$message))
  }

  if (isTRUE(modules$M7$on)) {
    tryCatch({
      r <- check_m7(ds_for_module("M7"), roles, modules)
      findings_list$m7 <- r$findings
      stats_list$M7 <- r$stats
    }, error = function(e) message("M7: ", e$message))
  }

  if (isTRUE(modules$M8$on)) {
    tryCatch({
      findings_list$m8 <- check_m8(ds_for_module("M8"), roles, modules)$findings
    }, error = function(e) message("M8: ", e$message))
  }

  # ---- M9 Field Request: custom checks only (fully AI-authored per project) ---
  if (isTRUE(modules$M9$on) || length(modules$M9$custom %||% character()) > 0) {
    custom <- modules$M9$custom %||% character()
    custom_full_data <- modules$M9$custom_full_data %||% character()
    if (!is.null(code_output_dir) && length(custom)) {
      for (cname in custom) {
        if (!nzchar(cname)) next
        cfile <- hfc_path(code_output_dir, "code", "checks", paste0(cname, ".R"))
        if (!file.exists(cfile)) {
          message("Custom check missing: ", cfile)
          next
        }
        tryCatch({
          env <- new.env(parent = globalenv())
          sys.source(cfile, envir = env)
          fn_name <- paste0("run_", cname)
          if (!exists(fn_name, envir = env, mode = "function")) {
            message("Custom check ", cname, " has no ", fn_name, "()")
            next
          }
          ds_custom <- if (cname %in% custom_full_data) ds_full else ds
          out <- env[[fn_name]](ds_custom, roles)
          if (!is.null(out) && nrow(out) > 0) {
            if (!"check_module" %in% names(out)) out$check_module <- "M9"
            findings_list[[paste0("custom_", cname)]] <- out
          }
        }, error = function(e) message("Custom ", cname, ": ", e$message))
      }
    }
  }

  if (isTRUE(modules$M10$on)) {
    tryCatch({
      findings_list$m10 <- check_m10(ds_for_module("M10"), roles, modules)$findings
    }, error = function(e) message("M10: ", e$message))
  }

  if (isTRUE(modules$M11$on)) {
    tryCatch({
      stats_list$M11 <- check_m11(ds_for_module("M11"), roles, modules)$stats
    }, error = function(e) message("M11: ", e$message))
  }

  # ---- M12 Balance Tables: rendered directly by render_balance_tables_body(),
  # outside this findings/stats pipeline entirely.

  # ---- M13 Media files (delegated to media.R) --------------------------
  if (isTRUE(modules$M13$on) && exists("run_m13_media_checks", mode = "function")) {
    tryCatch({
      findings_list$m13 <- run_m13_media_checks(ds_for_module("M13"), roles, modules)
    }, error = function(e) message("M13: ", e$message))
  }

  if (isTRUE(modules$M14$on)) {
    tryCatch({
      findings_list$m14 <- check_m14(ds_for_module("M14"), roles, modules)$findings
    }, error = function(e) message("M14: ", e$message))
  }

  findings <- bind_rows(findings_list)
  if (nrow(findings) == 0) findings <- empty_findings()
  findings <- dedupe_finding_ids(findings)
  list(findings = findings, stats = stats_list)
}

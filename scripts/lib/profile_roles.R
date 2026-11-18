pick_first <- function(nms, patterns) {
    for (p in patterns) {
        hit <- grep(p, nms, ignore.case = TRUE, value = TRUE)
        if (length(hit)) return(hit[[1]])
    }
    NA_character_
}

#' Candidate completion-indicator columns (M1).
detect_completion_candidates <- function(ds, n = 3L) {
    nms <- names(ds)
    hit <- grep("complete|submitted|finished|^result$|^status$|^outcome$|disposition|interview_status", nms, ignore.case = TRUE, value = TRUE)
    utils::head(hit, n)
}

#' Candidate primary/secondary sample-designation columns (M1's fallback
#' completion signal, when there's no roster and no explicit status column —
#' every row IS a completed survey, but composed of a primary + secondary
#' pool). Requires a name-pattern hit AND a plausible 2-value shape.
PRIMARY_SECONDARY_NAME_PATTERN <- "sample_type|^primary$|resp_type|respondent_type|sample_status"
PRIMARY_SECONDARY_VALUE_PATTERN <- "^(primary|secondary|1|2)$"
detect_primary_secondary_col <- function(ds) {
    nms <- names(ds)
    name_hit <- nms[grepl(PRIMARY_SECONDARY_NAME_PATTERN, nms, ignore.case = TRUE)]
    hit <- name_hit[vapply(name_hit, function(col) {
        x <- tolower(trimws(as.character(ds[[col]])))
        vals <- unique(x[!is.na(x) & nzchar(x)])
        length(vals) == 2 && all(grepl(PRIMARY_SECONDARY_VALUE_PATTERN, vals, ignore.case = TRUE))
    }, logical(1))]
    if (length(hit)) hit[[1]] else NA_character_
}

#' Values in a completion-status column that read as "this survey happened."
#' Matched against the column's own distinct values (not a fixed vocabulary
#' alone), so e.g. "Submitted" or "Yes" are recognized even though they
#' aren't literally "Complete".
COMPLETION_COMPLETE_VALUE_PATTERN <- "^(complete|completed|yes|submitted|finished|success|successful|1)$"

#' Detect which completion-signal type(s) are present in this dataset. The
#' agent surfaces ALL types found — this function does NOT silently
#' prioritize when more than one applies; the required-gate window's
#' completion tab (SKILL.md A1) is responsible for flagging that as a
#' special case rather than picking for the user.
#' `roster_candidate`: the agent's own roster/target-file determination,
#' threaded in from role_map.yaml's `roster_file_path` (NULL when there's no
#' roster).
#' Returns list(types = character() subset of "status"/"primary_secondary"/
#' "roster", status_col=, status_complete_values=, ps_col=, primary_value=,
#' roster_candidate=).
detect_completion_signal <- function(ds, roster_candidate = NULL) {
    status_col <- pick_first(names(ds), c(
        "^result$", "^status$", "^outcome$", "disposition", "interview_status",
        "^complete$", "^completed$", "submitted", "finished"
    ))
    status_complete_values <- character()
    if (!is.na(status_col)) {
        vals <- unique(trimws(as.character(ds[[status_col]])))
        vals <- vals[!is.na(vals) & nzchar(vals)]
        status_complete_values <- vals[grepl(COMPLETION_COMPLETE_VALUE_PATTERN, vals, ignore.case = TRUE)]
        # A status-like column only counts as a real signal if it actually
        # has BOTH complete-looking and non-complete-looking values — a
        # column where every value reads as "complete" carries no
        # filtering information (nothing to distinguish).
        if (!length(status_complete_values) || length(status_complete_values) == length(vals)) {
            status_col <- NA_character_
        }
    }

    ps_col <- detect_primary_secondary_col(ds)
    primary_value <- NA_character_
    if (!is.na(ps_col)) {
        vals <- unique(trimws(as.character(ds[[ps_col]])))
        vals <- vals[!is.na(vals) & nzchar(vals)]
        hit <- vals[grepl("primary|^1$", vals, ignore.case = TRUE)]
        primary_value <- if (length(hit)) hit[[1]] else vals[[1]]
    }

    types <- c(
        if (!is.na(status_col)) "status",
        if (!is.na(ps_col)) "primary_secondary",
        if (!is.null(roster_candidate)) "roster"
    )

    list(
        types = types,
        status_col = status_col, status_complete_values = status_complete_values,
        ps_col = ps_col, primary_value = primary_value,
        roster_candidate = roster_candidate
    )
}

#' Finds the machine-generated unique submission ID (SurveyCTO/ODK
#' KEY/uuid/instanceID) — distinct from Entity ID, which a respondent can
#' legitimately share across rows.
ID_NAME_PATTERN <- "studentid|hhid|household|respondent|farmerid|^id$|uuid|submission|key$|instanceid|caseid|interview"
detect_unique_key_column <- function(ds, exclude = character()) {
    is_fully_unique <- function(col) {
        x <- ds[[col]]
        x_chr <- as.character(x)
        if (any(is.na(x) | !nzchar(x_chr))) return(FALSE)
        length(unique(x_chr)) == nrow(ds)
    }
    key_col <- pick_first(names(ds), "^key$")
    if (!is.na(key_col)) return(key_col)

    name_cand <- pick_first(names(ds), c("uuid", "instanceid"))
    if (!is.na(name_cand) && is_fully_unique(name_cand)) return(name_cand)

    nms <- setdiff(names(ds), exclude)
    candidates <- nms[vapply(nms, is_fully_unique, logical(1))]
    if (!length(candidates)) return(NA_character_)
    pref <- candidates[grepl(ID_NAME_PATTERN, candidates, ignore.case = TRUE)]
    if (length(pref)) return(pref[[1]])
    candidates[[1]]
}

# Fills in the handful of fields that must be recomputed fresh from the data
# on every run (completion-signal detection, the unique submission key,
# weekend-flag default, last date seen, derived has_* booleans) on top of
# `roles`, which the agent has already written to role_map.yaml with every
# structural field (Entity ID, Group, Enumerator, Start/End/Duration,
# GPS/Age/Assent/Consent columns, media columns, name fields, country,
# form-version column, duplicate-key extras, section time pairs, ordinal
# variables — see references/role_map_schema.md). Never overwrites a field
# already present in `roles`.
profile_roles <- function(ds, roles, media_folder = NA_character_) {
    nms <- names(ds)

    roles$entity_id_sep <- roles$entity_id_sep %||% " / "
    roles$dup_key_extra <- roles$dup_key_extra %||% character()
    roles$country_mode <- roles$country_mode %||% "single"
    roles$entity_display <- roles$entity_display %||% "id"
    roles$enumerator_display <- roles$enumerator_display %||% "name"
    roles$group_display <- roles$group_display %||% "name"

    roles$media_folder <- if (!is.null(media_folder) && length(media_folder) && !is.na(media_folder[[1]]) &&
                            nzchar(as.character(media_folder[[1]]))) {
        as.character(media_folder[[1]])
    } else {
        NA_character_
    }
    roles$media_folder_found <- !is.na(roles$media_folder) && nzchar(roles$media_folder) &&
        dir.exists(roles$media_folder)

    roles$completion_var_candidates <- detect_completion_candidates(ds, n = 3L)

    roster_candidate <- if (!is.null(roles$roster_file_path) && length(roles$roster_file_path) &&
                            !is.na(roles$roster_file_path) && nzchar(roles$roster_file_path)) {
        list(path = roles$roster_file_path)
    } else NULL
    completion_signal <- detect_completion_signal(ds, roster_candidate = roster_candidate)
    roles$completion_signal_types <- completion_signal$types
    roles$completion_status_col <- completion_signal$status_col
    roles$completion_status_complete_values <- completion_signal$status_complete_values
    roles$completion_primary_secondary_col <- completion_signal$ps_col
    roles$completion_primary_value <- completion_signal$primary_value
    roles$completion_roster_candidate <- completion_signal$roster_candidate
    roles$completion_primary_signal <- roles$completion_primary_signal %||%
        (if (length(completion_signal$types) >= 1) completion_signal$types[[1]] else NA_character_)

    roles$key <- detect_unique_key_column(ds, exclude = c(
        roles$entity_id, roles$group, roles$enum, roles$x, roles$y,
        roles$entity_name_field, roles$group_name, roles$enum_name,
        roles$audio_file_cols, roles$image_file_cols
    ))

    roles$has_gps <- !is.na(roles$x %||% NA_character_) && !is.na(roles$y %||% NA_character_)
    roles$has_enum <- !is.na(roles$enum %||% NA_character_)
    roles$has_group <- !is.na(roles$group %||% NA_character_)
    roles$has_consentish <- !is.na(roles$assent %||% NA_character_) || !is.na(roles$consent %||% NA_character_) ||
        !is.na(roles$audio_flag %||% NA_character_)
    roles$has_media <- length(roles$audio_file_cols %||% character()) > 0 || length(roles$image_file_cols %||% character()) > 0

    date_col <- if (!is.na(roles$end %||% NA_character_)) roles$end else (roles$start %||% NA_character_)
    roles$last_date_candidate <- if (!is.na(date_col) && date_col %in% nms) {
        dt <- suppressWarnings(as.Date(as.character(ds[[date_col]])))
        if (all(is.na(dt))) NA_character_ else as.character(max(dt, na.rm = TRUE))
    } else NA_character_

    # Weekend-flagging default: flag weekends by default only when weekend
    # submission volume is low relative to weekdays (i.e. weekend work
    # looks atypical for this project).
    roles$flag_weekend_default <- TRUE
    if (!is.na(roles$start %||% NA_character_) && roles$start %in% nms) {
        wknd_dates <- suppressWarnings(as.Date(as.character(ds[[roles$start]])))
        wknd_dates <- wknd_dates[!is.na(wknd_dates)]
        if (length(wknd_dates)) {
        wknd_wday <- as.integer(format(wknd_dates, "%u"))
        is_wknd <- wknd_wday %in% c(6, 7)
        n_weekend_days <- length(unique(wknd_dates[is_wknd]))
        n_weekday_days <- length(unique(wknd_dates[!is_wknd]))
        avg_weekend <- if (n_weekend_days > 0) sum(is_wknd) / n_weekend_days else 0
        avg_weekday <- if (n_weekday_days > 0) sum(!is_wknd) / n_weekday_days else NA_real_
        ratio <- if (!is.na(avg_weekday) && avg_weekday > 0) avg_weekend / avg_weekday else NA_real_
        roles$flag_weekend_default <- is.na(ratio) || ratio < 0.25
        }
    }

    roles
}

default_modules <- function(roles) {
    audio_cols <- utils::head(roles$audio_file_cols %||% character(), 5)
    image_cols <- utils::head(roles$image_file_cols %||% character(), 5)

    important_vars <- roles$important_vars %||% character()
    ordinal_vars <- roles$ordinal_vars %||% character()
    m7_vars <- unique(c(important_vars, roles$missingness_extra_vars %||% character()))

    # M1's completion-by-group breakdown defaults to Treatment/Control;
    # geography is only added when there's no Treatment/Control column, or
    # you've explicitly opted in to it alongside it.
    m1_tc <- roles$treatment_control_col %||% NA_character_
    m1_geo <- roles$geo_group_col %||% NA_character_
    m1_group_vars <- if (!is.na(m1_tc)) {
        c(m1_tc, if (isTRUE(roles$geo_group_opted_in)) m1_geo else NA_character_)
    } else {
        m1_geo
    }
    m1_group_vars <- m1_group_vars[!is.na(m1_group_vars)]

    list(
        M1 = list(
        on = TRUE,
        # M1 alone sees the full, unfiltered dataset — every other module
        # sees the completed subset only.
        full_data = TRUE,
        completion_var = if (length(roles$completion_var_candidates)) roles$completion_var_candidates[[1]] else NA_character_,
        completion_signal = roles$completion_primary_signal %||% "row_missingness",
        # Confirmed screening question(s), in form order, plus each one's
        # pass value and a human label. Blank until confirmed for this survey.
        gate_cols = character(),
        gate_pass_values = list(),
        gate_labels = list(),
        # Per-failing-value substantive reason (e.g. "Household absent"),
        # not just which gate failed. gate_labels is the fallback.
        gate_fail_reasons = list(),
        # gate_min_date: a gate added to the form partway through data
        # collection is exempted for submissions before it existed.
        # governing_gate: a later gate (typically consent) that can override
        # an earlier one still reading as failed.
        gate_min_date = character(),
        governing_gate = NA_character_,
        # Unset skips this check entirely.
        daily_target_per_enum = NA_real_,
        # Replacement-sample analysis: which roster column marks Primary vs
        # Replacement, which values count as Primary, the replacement-queue
        # rank column, and the roster's own group column. Blank skips it.
        replacement_status_col = NA_character_,
        replacement_primary_values = "primary",
        # Set true ONLY when the user confirms the roster has no primary/
        # replacement column (every roster respondent is then primary); never
        # assumed - the build stops and asks while a roster has neither.
        roster_all_primary = NA,
        # How submitted IDs missing from the roster are treated, as chosen by
        # the user when the build asks: "non_primary" or "exclude".
        offroster_handling = NA_character_,
        replacement_rank_col = NA_character_,
        replacement_group_col = NA_character_,
        # Maps roster status values beyond Primary/Replacement (Rejected/
        # Unavailable/Rescheduled/Other) to a non-completion reason for
        # respondents never reached at all. Blank skips it.
        nonstart_status_col = NA_character_,
        nonstart_reason_map = list(),
        group_vars = m1_group_vars,
        by_enum = TRUE,
        by_date = TRUE
        ),
        M2 = list(on = TRUE, full_data = FALSE, id = roles$entity_id, extra_keys = roles$dup_key_extra %||% character()),
        M3 = list(
        on = TRUE,
        full_data = FALSE,
        version_col = roles$form_version_col %||% NA_character_,
        version_map = list()
        ),
        M4 = list(
        on = TRUE,
        full_data = FALSE,
        duration = roles$duration,
        sd_rule = 3,
        section_map = list(),
        section_pairs = list(),
        by_enum = TRUE,
        # One-sided by default: only a suspiciously short duration is
        # flagged. Flagging unusually long ones is an opt-in advanced flag.
        advanced_long_flag = list(on = FALSE)
        ),
        M5 = list(
        on = TRUE,
        full_data = FALSE,
        flag_weekend = isTRUE(roles$flag_weekend_default %||% TRUE),
        evening_hour = 20,
        morning_hour = 6
        ),
        M6 = list(
        on = TRUE,
        full_data = FALSE,
        vars = utils::head(important_vars, 10),
        sd_rule = 3,
        # "sd" (default): mean +/- sd_rule*SD. "fixed": a fixed absolute
        # range per variable (fixed_thresholds), for known plausible bounds.
        outlier_mode = "sd",
        fixed_thresholds = list()
        ),
        M7 = list(
        on = TRUE,
        full_data = FALSE,
        vars = m7_vars,
        sentinel_codes = character(),
        # A variable only earns a row in the OVERALL table past this
        # population-missingness threshold.
        var_issue_threshold = 0.95,
        # enum_pool_threshold/enum_pct_threshold configure the opt-in
        # advanced_enum_flag below.
        enum_pool_threshold = 0.9,
        enum_pct_threshold = 0.5,
        # Descriptive only by default. Enumerator-level flagging is an
        # opt-in advanced flag, off by default.
        advanced_enum_flag = list(on = FALSE)
        ),
        M8 = list(
        on = length(ordinal_vars) > 0,
        full_data = FALSE,
        ordinal_vars = utils::head(ordinal_vars, 15),
        # Enumerator-level: per enumerator per day (minimum 3 surveys that
        # day). Survey-level (within one submission) is a separate check.
        enum_threshold_pct = 1.0,
        survey_threshold_pct = 0.9
        ),
        M9 = list(
        on = FALSE,
        full_data = FALSE,
        enabled = character(),
        custom = character(),
        custom_full_data = character()
        ),
        M10 = list(
        on = isTRUE(roles$has_gps),
        full_data = FALSE,
        x = roles$x,
        y = roles$y,
        # Pure visualization by default. Distance-outlier flagging is an
        # opt-in advanced flag, off by default.
        advanced_distance_flag = list(on = FALSE, threshold_m = 300)
        ),
        M11 = list(on = TRUE, full_data = FALSE, vars = utils::head(important_vars, 10), by_enum = TRUE, max_n = 10L),
        M12 = list(
        on = FALSE,
        full_data = FALSE,
        # No auto-detection — which covariates/groupings matter is a
        # setup-confirm question. Each grouping: group_col, group_label,
        # covariates, other_group_col, roster_value_map.
        groupings = list()
        ),
        M13 = list(
        on = isTRUE(roles$has_media),
        full_data = FALSE,
        audio_cols = audio_cols,
        image_cols = image_cols,
        other_cols = roles$qualitative_text_cols %||% character()
        ),
        M14 = list(
        on = isTRUE(roles$has_consentish),
        full_data = FALSE,
        assent = roles$assent,
        consent = roles$consent,
        audio = roles$audio_flag
        )
    )
}

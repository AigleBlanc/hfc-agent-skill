# Checks the confirmed config for structural problems before a build runs,
# so a bad config surfaces as a clear message instead of a silently-empty
# table downstream.

#' Structural fields the agent must determine and write to role_map.yaml
#' itself (see references/role_map_schema.md) — present even as NA/empty
#' when a field doesn't apply to this survey, since nothing fills these in
#' automatically any more.
REQUIRED_ROLE_FIELDS <- c(
    "entity_id", "entity_name_field", "group", "group_name", "enum", "enum_name",
    "start", "end", "duration", "x", "y", "age", "assent", "consent", "audio_flag",
    "audio_file_cols", "image_file_cols", "consent_image", "assent_image",
    "form_version_col", "dup_key_extra", "section_time_pairs", "ordinal_vars",
    "data_file_path"
)

#' Checks the config for problems. Column-existence checks only run when
#' `ds` is given.
validate_modules_config <- function(modules, roles, ds = NULL) {
    errors <- character(); warnings <- character()
    has_ds <- !is.null(ds)
    col_exists <- function(col) !is.na(col) && nzchar(col) && (!has_ds || col %in% names(ds))
    # Not a pure function of (label, col): it reads the CURRENT value of the
    # outer `errors` via lexical scoping (so it must be called after every
    # prior error has already been appended) and returns the appended
    # vector — never mutates the outer binding itself. Every call site must
    # therefore reassign the result (`errors <- missing_col(...)`), or the
    # appended error is silently dropped.
    missing_col <- function(label, col) {
        if (!is.na(col) && nzchar(col) && has_ds && !col %in% names(ds)) {
        errors <- c(errors, sprintf("%s: column '%s' is configured but not found in the data.", label, col))
        }
        errors
    }
    blank <- function(v) is.null(v) || (length(v) == 1 && (is.na(v) || !nzchar(as.character(v))))

    for (field in REQUIRED_ROLE_FIELDS) {
        if (!field %in% names(roles)) {
        errors <- c(errors, sprintf(
            "role_map.yaml is missing '%s' — determine it from the data profile and write it, even as NA/empty if it doesn't apply to this survey.",
            field
        ))
        }
    }
    if (blank(roles$entity_id)) {
        errors <- c(errors, "role_map.yaml's 'entity_id' is blank — every survey needs a respondent/case identifier column.")
    }
    if (blank(roles$data_file_path)) {
        errors <- c(errors, "role_map.yaml's 'data_file_path' is blank — which file is the microdata must be determined before anything else.")
    }

    if (identical(roles$country_mode, "multi")) {
        map <- roles$country_timezone_map %||% list()
        if (has_ds && !blank(roles$country_col) && roles$country_col %in% names(ds)) {
        vals <- unique(as.character(ds[[roles$country_col]]))
        vals <- vals[!is.na(vals) & nzchar(vals)]
        no_tz <- vals[vapply(vals, function(v) blank(map[[v]]), logical(1))]
        if (length(no_tz)) {
            errors <- c(errors, sprintf("country_timezone_map has no timezone for: %s.", paste(no_tz, collapse = ", ")))
        }
        }
    } else if (blank(roles$timezone)) {
        errors <- c(errors, "role_map.yaml's 'timezone' is not resolved — every project needs an IANA timezone before M5/M1's timing checks can run.")
    }

    m1 <- modules$M1 %||% list()

    gate_cols <- m1$gate_cols %||% character()
    for (nm in c("gate_pass_values", "gate_labels", "gate_min_date")) {
        keys <- names(m1[[nm]] %||% list())
        orphan <- setdiff(keys, gate_cols)
        if (length(orphan)) {
        warnings <- c(warnings, sprintf("M1.%s has entr(y/ies) for column(s) not in gate_cols: %s.", nm, paste(orphan, collapse = ", ")))
        }
    }
    governing_gate <- m1$governing_gate %||% NA_character_
    if (!is.na(governing_gate) && !governing_gate %in% gate_cols) {
        errors <- c(errors, sprintf("M1.governing_gate ('%s') is not one of the confirmed gate_cols.", governing_gate))
    }
    if (has_ds) {
        for (gc in gate_cols) errors <- missing_col("M1.gate_cols", gc)
    }
    if (identical(m1$completion_signal, "gating") && !length(gate_cols)) {
        warnings <- c(warnings, "M1.completion_signal is 'gating' but gate_cols is empty — completion will fall back to 'always complete.'")
    }
    if (identical(m1$completion_signal, "roster") && (is.null(roles$completion_roster_candidate) || is.na(roles$completion_roster_candidate$path %||% NA_character_))) {
        errors <- c(errors, "M1.completion_signal is 'roster' but no roster/target file is configured (roles$completion_roster_candidate).")
    }

    m6 <- modules$M6 %||% list()
    outlier_mode <- m6$outlier_mode %||% "sd"
    if (!outlier_mode %in% c("sd", "fixed")) {
        errors <- c(errors, sprintf("M6.outlier_mode is '%s' — must be 'sd' or 'fixed'.", outlier_mode))
    }
    if (identical(outlier_mode, "fixed")) {
        ft <- m6$fixed_thresholds %||% list()
        if (!length(ft)) {
        warnings <- c(warnings, "M6.outlier_mode is 'fixed' but fixed_thresholds is empty — every variable will fall back to the SD rule.")
        }
        uncovered <- setdiff(m6$vars %||% character(), names(ft))
        if (length(uncovered) && length(ft)) {
        warnings <- c(warnings, sprintf("M6.fixed_thresholds doesn't cover: %s (falls back to the SD rule for these).", paste(uncovered, collapse = ", ")))
        }
        for (vc in names(ft)) {
        b <- ft[[vc]]
        low <- suppressWarnings(as.numeric(b$low %||% NA_real_)); high <- suppressWarnings(as.numeric(b$high %||% NA_real_))
        if (is.na(low) && is.na(high)) {
            warnings <- c(warnings, sprintf("M6.fixed_thresholds[['%s']] has neither low nor high set — this variable won't flag anything.", vc))
        } else if (!is.na(low) && !is.na(high) && low >= high) {
            errors <- c(errors, sprintf("M6.fixed_thresholds[['%s']]: low (%s) must be less than high (%s).", vc, low, high))
        }
        }
    }
    if (has_ds) for (vc in m6$vars %||% character()) errors <- missing_col("M6.vars", vc)

    for (i in seq_along(modules$M12$groupings %||% list())) {
        g <- modules$M12$groupings[[i]]
        gl <- sprintf("M12.groupings[[%d]] ('%s')", i, g$group_label %||% g$group_col %||% i)
        if (is.null(g$group_col) || is.na(g$group_col)) {
        errors <- c(errors, sprintf("%s has no group_col configured.", gl))
        } else if (has_ds) {
        errors <- missing_col(gl, g$group_col)
        }
        if (!is.null(g$other_group_col) && !is.na(g$other_group_col) && has_ds) {
        errors <- missing_col(paste0(gl, ".other_group_col"), g$other_group_col)
        }
        cov <- g$covariates %||% character()
        if (has_ds) for (cv in cov) errors <- missing_col(paste0(gl, ".covariates"), cv)
    }

    if (has_ds) {
        for (col in c(modules$M2$id %||% character(), modules$M2$extra_keys %||% character())) errors <- missing_col("M2", col)
        if (!is.null(modules$M3$version_col)) errors <- missing_col("M3.version_col", modules$M3$version_col %||% NA_character_)
        if (!is.null(modules$M4$duration)) errors <- missing_col("M4.duration", modules$M4$duration %||% NA_character_)
        for (vc in modules$M7$vars %||% character()) errors <- missing_col("M7.vars", vc)
        for (vc in modules$M8$ordinal_vars %||% character()) errors <- missing_col("M8.ordinal_vars", vc)
        for (col in c(modules$M13$audio_cols %||% character(), modules$M13$image_cols %||% character(), modules$M13$other_cols %||% character())) {
        errors <- missing_col("M13", col)
        }
        for (nm in c("assent", "consent", "audio")) {
        col <- modules$M14[[nm]] %||% NA_character_
        if (!is.na(col)) errors <- missing_col(paste0("M14.", nm), col)
        }
    }

    # Flags a gap in M3's version_map date coverage.
    vm <- modules$M3$version_map %||% list()
    if (length(vm) >= 2) {
        starts <- suppressWarnings(as.Date(vapply(vm, function(v) as.character(v$date_start %||% NA), character(1))))
        ends <- suppressWarnings(as.Date(vapply(vm, function(v) as.character(v$date_end %||% NA), character(1))))
        ord <- order(starts)
        starts_o <- starts[ord]; ends_o <- ends[ord]
        for (i in seq_len(length(starts_o) - 1)) {
        if (!is.na(ends_o[i]) && !is.na(starts_o[i + 1]) && ends_o[i] + 1 < starts_o[i + 1]) {
            warnings <- c(warnings, sprintf(
            "M3.version_map has a gap: %s to %s falls between two configured windows and will never validate.",
            format(ends_o[i] + 1), format(starts_o[i + 1] - 1)
            ))
        }
        }
    }

    list(ok = length(errors) == 0, errors = unique(errors), warnings = unique(warnings))
}

#' Human-readable summary. `stop_on_error` stops the build on a real error.
format_config_validation <- function(v, stop_on_error = FALSE) {
    if (isTRUE(v$ok) && !length(v$warnings)) {
        msg <- "Config validation: OK."
        if (stop_on_error) message(msg)
        return(msg)
    }
    lines <- character()
    if (length(v$errors)) lines <- c(lines, paste0("ERROR: ", v$errors))
    if (length(v$warnings)) lines <- c(lines, paste0("Warning: ", v$warnings))
    msg <- paste0("Config validation:\n  ", paste(lines, collapse = "\n  "))
    if (stop_on_error && !isTRUE(v$ok)) stop(msg)
    if (stop_on_error) message(msg)
    msg
}

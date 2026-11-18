# Shared helpers for scripts/lib

# Null-coalescing: falls through to `b` on NULL, zero-length, NA, or "".
`%||%` <- function(a, b) {
    if (is.null(a) || length(a) == 0) return(b)
    if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
    a
}

# Coerce a (possibly labelled) column to plain numeric, NA on failure.
safe_num <- function(x) {
    if (inherits(x, "haven_labelled")) x <- as.vector(x)
    suppressWarnings(as.numeric(x))
}

# Numeric codes that mean "missing / don't know / refused" rather than a real
# measurement. Applied by default to every numeric statistic (M6 outliers, M11,
# M12 covariates, M4 durations, M8, M7) so they are never flagged or averaged.
DEFAULT_NA_CODES <- c(-99, -999, -9999, 999, 9999, 99999)

# The NA codes in force for one variable: the defaults, plus whatever the user
# added in `modules$M7$sentinel_codes` (a plain vector shared by every
# variable, or a per-variable named list). The user's codes ADD to the defaults;
# a default cannot be removed. Returned as numeric.
na_codes_for <- function(modules, vc = NULL) {
    user <- modules$M7$sentinel_codes %||% NULL
    extra <- if (is.null(user)) numeric() else if (is.list(user) && !is.null(names(user))) {
        if (!is.null(vc) && !is.null(user[[vc]])) user[[vc]] else numeric()
    } else user
    extra <- suppressWarnings(as.numeric(unlist(extra)))
    unique(c(DEFAULT_NA_CODES, extra[is.finite(extra)]))
}

# safe_num() with every value in `codes` (default: the default NA codes) set
# to NA.
clean_num <- function(x, codes = DEFAULT_NA_CODES) {
    v <- safe_num(x)
    v[!is.na(v) & v %in% codes] <- NA_real_
    v
}

# Shared rounding for every measured value shown in the report — 1 decimal.
round1 <- function(x) round(suppressWarnings(as.numeric(x)), 1)

# One finding-date-per-row, as a bare "YYYY-MM-DD" string, preferring
# start_date and falling back to end_date.
finding_date_vec <- function(df) {
    if (is.null(df) || !nrow(df)) return(character())
    sd <- if ("start_date" %in% names(df)) as.character(df$start_date) else rep(NA_character_, nrow(df))
    ed <- if ("end_date" %in% names(df)) as.character(df$end_date) else rep(NA_character_, nrow(df))
    raw <- ifelse(!is.na(sd) & nzchar(sd), sd, ed)
    suppressWarnings(as.character(as.Date(raw)))
}

# Clean, human-readable name for a raw survey column (e.g. price_rice_kg ->
# "Rice price (kg)"). Falls back to the raw column name when unset.
var_label <- function(colname, roles) {
    labels <- roles$var_labels %||% list()
    vapply(colname, function(cn) {
        if (is.na(cn) || !nzchar(as.character(cn))) return(as.character(cn))
        labels[[cn]] %||% cn
    }, character(1), USE.NAMES = FALSE)
}

#' Decodes a value-labelled column (e.g. 1/2/3 with attached names) to its
#' label text. A plain column passes through unchanged.
decode_labelled_chr <- function(x) {
    if (inherits(x, "haven_labelled")) {
        return(as.character(haven::as_factor(x)))
    }
    as.character(x)
}

#' Per-row display name for an enumerator/group ID column: the separate
#' name column when found, else the ID's own decoded value labels, else
#' blank. Never applied to the respondent ID, which stays anonymous.
resolve_unit_name <- function(ds, id_col, name_col) {
    if (!is.null(name_col) && !is.na(name_col) && name_col %in% names(ds)) {
        return(as.character(ds[[name_col]]))
    }
    if (!is.null(id_col) && !is.na(id_col) && id_col %in% names(ds) &&
        inherits(ds[[id_col]], "haven_labelled")) {
        return(decode_labelled_chr(ds[[id_col]]))
    }
    rep("", nrow(ds))
}

# All built artifacts live under <Code Output Directory>/hfc/.
hfc_root <- function(code_output_dir) {
    file.path(code_output_dir, "hfc")
}

hfc_path <- function(code_output_dir, ...) {
    file.path(hfc_root(code_output_dir), ...)
}

# A short, stable label for this survey (the Input Data Directory's name).
derive_project_id <- function(input_data_dir) {
    basename(normalizePath(input_data_dir, mustWork = FALSE))
}

# Read survey microdata (.dta/.csv/.xlsx), optionally subsampled with a fixed seed.
load_microdata <- function(path, sample_n = NA_integer_) {
    suppressPackageStartupMessages({
    library(haven); library(readr); library(readxl)
    })
    ext <- tolower(tools::file_ext(path))
    ds <- if (ext == "dta") {
        read_dta(path)
    } else if (ext == "csv") {
        read_csv(path, show_col_types = FALSE, guess_max = 10000)
    } else if (ext %in% c("xlsx", "xls")) {
        read_excel(path)
    } else {
        stop("Unsupported microdata type: ", ext)
    }
    if (!is.na(sample_n) && sample_n > 0 && nrow(ds) > sample_n) {
    set.seed(42)
    ds <- ds[sample.int(nrow(ds), sample_n), , drop = FALSE]
    }
    ds
}

# Writes fixed data to an "Updated Data" folder inside your HFC Output
# Directory — the original is never touched. Each fix pass updates this
# one evolving file.
write_intermediate <- function(ds, onedrive_output_dir, stem, ext) {
    suppressPackageStartupMessages({ library(haven); library(readr); library(openxlsx) })
    ds <- as.data.frame(lapply(ds, function(col) {
        if (inherits(col, "haven_labelled")) return(as.vector(col))
        col
    }), stringsAsFactors = FALSE)
    dir <- file.path(onedrive_output_dir, "Updated Data")
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    ext <- tolower(ext)
    out <- file.path(dir, paste0(stem, ".", ext))
    if (ext == "dta") {
        write_dta(ds, out)
    } else if (ext == "csv") {
        write_csv(ds, out)
    } else if (ext %in% c("xlsx", "xls")) {
        wb <- createWorkbook()
        addWorksheet(wb, "data")
        writeData(wb, "data", ds)
        saveWorkbook(wb, out, overwrite = TRUE)
    } else {
        out <- file.path(dir, paste0(stem, ".csv"))
        write_csv(ds, out)
    }
    normalizePath(out)
}

# Loads the latest fixed version if one exists, else the original.
load_latest_dataset <- function(input_data_dir, onedrive_output_dir, data_file, sample_n = NA_integer_) {
    stem <- tools::file_path_sans_ext(basename(data_file))
    ext <- tolower(tools::file_ext(data_file))
    updated_data_path <- file.path(onedrive_output_dir, "Updated Data", paste0(stem, ".", ext))
    path <- if (file.exists(updated_data_path)) updated_data_path else file.path(input_data_dir, basename(data_file))
    load_microdata(path, sample_n = sample_n)
}

# Zero-row findings tibble with the standard column schema.
empty_findings <- function() {
    tibble::tibble(
        finding_id = character(), check_id = character(), check_module = character(),
        category = character(), issue = character(), submission_id = character(),
        group_id = character(), enumerator = character(),
        start_date = character(), end_date = character(),
        key = character(), value = character(), variable = character(),
        entity_name = character(), group_name = character(), enumerator_name = character(),
        arm_id = character(),
        sort_value = double()
    )
}

#' Resolves a display vector for an ID+name pair. "id" mode always shows
#' the raw ID (used for the respondent, anonymous by default); "name" shows
#' the name where available, else the ID (used for enumerator/group).
resolve_display_vec <- function(id_vals, name_vals, mode = "name") {
    id_vals <- as.character(id_vals)
    if (identical(mode, "id") || is.null(name_vals)) return(id_vals)
    name_vals <- as.character(name_vals)
    ifelse(!is.na(name_vals) & nzchar(name_vals), name_vals, id_vals)
}

#' Paste one or more ID columns into a single display/sort string.
#' `id_cols` is usually a single column name, but may be a character vector
#' when the survey's unique key is composite (e.g. household_id + member_id).
composite_id_string <- function(df, id_cols, sep = ":") {
    id_cols <- id_cols[!is.na(id_cols) & nzchar(as.character(id_cols))]
    id_cols <- id_cols[id_cols %in% names(df)]
    if (!length(id_cols)) return(rep("", nrow(df)))
    if (length(id_cols) == 1) return(as.character(df[[id_cols]]))
    parts <- lapply(id_cols, function(cn) as.character(df[[cn]]))
    do.call(paste, c(parts, list(sep = sep)))
}

# Builds a findings tibble from flagged rows, one row per finding.
mk_findings <- function(df, check_id, module, category, issue_chr, roles, value_col = NULL, variable_name = NULL,
                         sort_value_col = NULL) {
    if (is.null(df) || nrow(df) == 0) return(empty_findings())
    n <- nrow(df)
    sub_id <- if (".hfc_id_display" %in% names(df)) {
        as.character(df[[".hfc_id_display"]])
    } else {
        composite_id_string(df, roles$entity_id, roles$entity_id_sep %||% " / ")
    }
    var_suffix <- if (!is.null(variable_name) && nzchar(variable_name)) paste0(":", variable_name) else ""
    tibble::tibble(
        finding_id = paste0(tolower(module), ":", sub_id, var_suffix),
        check_id = check_id,
        check_module = module,
        category = category,
        issue = issue_chr,
        submission_id = sub_id,
        group_id = if (!is.null(roles$group) && roles$group %in% names(df)) as.character(df[[roles$group]]) else "",
        enumerator = if (!is.null(roles$enum) && roles$enum %in% names(df)) as.character(df[[roles$enum]]) else "",
        start_date = if (!is.null(roles$start) && roles$start %in% names(df)) as.character(df[[roles$start]]) else "",
        end_date = if (!is.null(roles$end) && roles$end %in% names(df)) as.character(df[[roles$end]]) else "",
        key = if (!is.null(roles$key) && roles$key %in% names(df)) as.character(df[[roles$key]]) else "",
        value = if (!is.null(value_col) && value_col %in% names(df)) decode_labelled_chr(df[[value_col]]) else "",
        variable = variable_name %||% "",
        entity_name = if (!is.null(roles$entity_name_field) && roles$entity_name_field %in% names(df)) as.character(df[[roles$entity_name_field]]) else "",
        group_name = resolve_unit_name(df, roles$group, roles$group_name),
        enumerator_name = resolve_unit_name(df, roles$enum, roles$enum_name),
        arm_id = if (!is.null(roles$treatment_control_col) && roles$treatment_control_col %in% names(df)) as.character(df[[roles$treatment_control_col]]) else "",
        sort_value = if (!is.null(sort_value_col) && sort_value_col %in% names(df)) suppressWarnings(as.numeric(df[[sort_value_col]])) else NA_real_
    )
}

#' One finding per aggregate unit (an enumerator or group/site), never one
#' per underlying submission row. `unit_df` needs a `unit_id` column (raw
#' ID) and optionally `unit_name`. `date_col`, if given, scopes the finding
#' to a single day; omitted, it's a dateless structural finding.
mk_aggregate_finding <- function(unit_df, check_id, module, category, issue_chr, roles,
                                  unit_type = c("enumerator", "group"),
                                  value_col = NULL, variable_name = NULL, sort_value_col = NULL,
                                  date_col = NULL) {
    unit_type <- match.arg(unit_type)
    if (is.null(unit_df) || nrow(unit_df) == 0) return(empty_findings())
    n <- nrow(unit_df)
    unit_id <- as.character(unit_df$unit_id)
    unit_name <- if ("unit_name" %in% names(unit_df)) as.character(unit_df$unit_name) else rep(NA_character_, n)
    unit_name <- ifelse(is.na(unit_name), "", unit_name)
    var_suffix <- if (!is.null(variable_name) && nzchar(variable_name)) paste0(":", variable_name) else ""
    date_vals <- if (!is.null(date_col) && date_col %in% names(unit_df)) as.character(unit_df[[date_col]]) else rep("", n)
    date_suffix <- ifelse(nzchar(date_vals), paste0(":", date_vals), "")
    tibble::tibble(
        finding_id = paste0(tolower(module), ":", unit_type, ":", unit_id, var_suffix, date_suffix),
        check_id = check_id,
        check_module = module,
        category = category,
        issue = if (length(issue_chr) == n) issue_chr else rep(issue_chr, n),
        submission_id = "",
        group_id = if (unit_type == "group") unit_id else "",
        enumerator = if (unit_type == "enumerator") unit_id else "",
        start_date = date_vals,
        end_date = date_vals,
        key = "",
        value = if (!is.null(value_col) && value_col %in% names(unit_df)) as.character(unit_df[[value_col]]) else "",
        variable = variable_name %||% "",
        entity_name = "",
        group_name = if (unit_type == "group") unit_name else "",
        enumerator_name = if (unit_type == "enumerator") unit_name else "",
        arm_id = "",
        sort_value = if (!is.null(sort_value_col) && sort_value_col %in% names(unit_df)) suppressWarnings(as.numeric(unit_df[[sort_value_col]])) else NA_real_
    )
}

#' Selects the full dataset or just the completed/surveyed subset for one
#' module — M1 needs the full picture, every other module defaults to
#' completed rows only.
ds_for_module_selection <- function(ds_full, mod_code, modules) {
    if (isTRUE(modules[[mod_code]]$full_data)) return(ds_full)
    if (!".hfc_completed" %in% names(ds_full) || all(ds_full$.hfc_completed)) return(ds_full)
    filtered <- ds_full[ds_full$.hfc_completed, , drop = FALSE]
    attr(filtered, "hfc_form_map") <- attr(ds_full, "hfc_form_map")
    filtered
}

#' One finding per duplicate-key group (M2 only), never one per duplicate
#' row — every submission's timestamp goes into Value instead (e.g. "2
#' submissions: 2026-08-13 03:16, 2026-08-13 04:01").
mk_duplicate_group_findings <- function(df, group_cols, id_cols, check_id, module, category, issue_chr, roles, time_col = NA_character_) {
    if (is.null(df) || nrow(df) == 0) return(empty_findings())
    group_cols <- group_cols[group_cols %in% names(df)]
    if (!length(group_cols)) return(empty_findings())
    grp_key <- composite_id_string(df, group_cols, sep = "")
    splits <- split(seq_len(nrow(df)), grp_key)
    rows <- lapply(splits, function(idx) {
        sub <- df[idx, , drop = FALSE]
        sub_id <- composite_id_string(sub[1, , drop = FALSE], id_cols, roles$entity_id_sep %||% " / ")
        times <- if (!is.na(time_col) && time_col %in% names(sub)) {
            format(parse_datetime_col(sub[[time_col]]), "%Y-%m-%d %H:%M")
        } else {
            rep(NA_character_, nrow(sub))
        }
        times <- times[!is.na(times)]
        val <- if (length(times)) {
            sprintf("%d submissions: %s", nrow(sub), paste(times, collapse = ", "))
        } else {
            sprintf("%d submissions", nrow(sub))
        }
        tibble::tibble(
            finding_id = paste0(tolower(module), ":", sub_id),
            check_id = check_id, check_module = module, category = category,
            issue = issue_chr, submission_id = sub_id,
            group_id = "", enumerator = "", start_date = "", end_date = "", key = "",
            value = val, variable = "",
            entity_name = "", group_name = "", enumerator_name = "", arm_id = "",
            sort_value = NA_real_
        )
    })
    dplyr::bind_rows(rows)
}

# Suffixes any repeated finding_id (:2, :3, ...) across the full combined
# findings tibble, keeping the first occurrence bare.
dedupe_finding_ids <- function(findings) {
    if (is.null(findings) || nrow(findings) == 0) return(findings)
    dupn <- ave(seq_len(nrow(findings)), findings$finding_id, FUN = seq_along)
    findings$finding_id <- ifelse(dupn > 1, paste0(findings$finding_id, ":", dupn), findings$finding_id)
    findings
}

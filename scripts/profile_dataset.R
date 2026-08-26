# Neutral data profiler for A1's setup — no classification, no scoring, no
# guessing. Prints structured JSON for the agent to read and reason over
# itself; every structural field it implies still has to be determined by
# the agent and written to role_map.yaml (see references/role_map_schema.md)
# — this script never writes role_map.yaml.
#
# Usage: Rscript profile_dataset.R
#   Mode "files"   — role_map.yaml has no data_file_path yet: lists every
#                    candidate file under the Input Data Directory with
#                    metadata (extension, size, row/col count, sheet names).
#   Mode "columns" — role_map.yaml has a data_file_path: loads that file and
#                    profiles every column (type, label, missingness,
#                    cardinality, a handful of sample values).

.resolve_skill <- function() {
    sp <- {
    ca <- commandArgs(trailingOnly = FALSE)
    fa <- grep("^--file=", ca, value = TRUE)
    if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
    }
    if (!is.na(sp) && file.exists(sp)) {
    return(normalizePath(file.path(dirname(sp), "..")))
    }
    if (file.exists(".claude/skills/hfc-agent-skill/scripts/lib/utils.R")) {
    return(normalizePath(".claude/skills/hfc-agent-skill"))
    }
    if (file.exists("hfc-agent-skill/scripts/lib/utils.R")) {
    return(normalizePath("hfc-agent-skill"))
    }
    if (file.exists("scripts/lib/utils.R")) return(normalizePath(".."))
    stop("Cannot locate hfc-agent-skill")
}
skill <- .resolve_skill()
lib <- file.path(skill, "scripts", "lib")
source(file.path(lib, "utils.R"))
source(file.path(lib, "discover.R"))
source(file.path(lib, "issue_store.R"))

suppressPackageStartupMessages({
    library(haven); library(readr); library(readxl); library(jsonlite)
})

ctx <- require_hfc_config_ready(skill)
cfg <- ctx$cfg

role_map_path <- hfc_path(cfg$code_output_dir, "config", "role_map.yaml")
saved <- if (file.exists(role_map_path)) yaml::read_yaml(role_map_path) else list()
data_path <- saved$data_file_path %||% NA_character_

emit <- function(x) cat(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), "\n")

if (is.na(data_path) || !nzchar(data_path) || !file.exists(data_path)) {
    disc <- discover_project(cfg$input_data_dir)
    emit(list(
        mode = "files",
        input_data_dir = disc$input_data_dir,
        status = disc$status,
        tabular_candidates = unname(disc$tabular_candidates),
        doc_candidates = disc$doc_candidates
    ))
    quit(save = "no", status = 0)
}

ds <- load_microdata(data_path)

col_label <- function(x) {
    lab <- tryCatch(attr(x, "label"), error = function(e) NULL)
    if (is.null(lab) || length(lab) != 1 || !nzchar(as.character(lab))) return(NA_character_)
    as.character(lab)[[1]]
}

profile_one <- function(col) {
    x <- ds[[col]]
    x_chr <- as.character(if (inherits(x, "haven_labelled")) haven::as_factor(x) else x)
    non_blank <- x_chr[!is.na(x_chr) & nzchar(trimws(x_chr))]
    samples <- utils::head(unique(non_blank), 8)
    samples <- vapply(samples, function(s) if (nchar(s) > 60) paste0(substr(s, 1, 60), "...") else s, character(1))
    list(
        name = col,
        type = class(x)[[1]],
        label = col_label(x),
        n_non_missing = length(non_blank),
        n_total = length(x_chr),
        pct_missing = round1(100 * (1 - length(non_blank) / max(1, length(x_chr)))),
        n_distinct = length(unique(non_blank)),
        sample_values = unname(samples)
    )
}

emit(list(
    mode = "columns",
    data_file_path = data_path,
    nrow = nrow(ds),
    ncol = ncol(ds),
    columns = lapply(names(ds), profile_one)
))

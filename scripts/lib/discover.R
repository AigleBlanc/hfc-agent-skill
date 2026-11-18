# Lists every candidate file inside the configured Input Data Directory and
# its subfolders — never anywhere else. No classification: which file is
# microdata, the form, a roster, or context reading is for the agent to
# decide from the metadata/content here, not a filename-pattern guess.

discover_project <- function(input_data_dir) {
    input_data_dir <- normalizePath(input_data_dir, mustWork = FALSE)
    if (!dir.exists(input_data_dir)) {
        return(list(
            input_data_dir = input_data_dir, tabular_candidates = list(),
            doc_candidates = character(), status = "missing_dir"
        ))
    }

    tabular_paths <- list.files(
        input_data_dir, pattern = "\\.(dta|csv|xlsx|xls)$", full.names = TRUE,
        ignore.case = TRUE, recursive = TRUE
    )
    tabular_paths <- unique(normalizePath(tabular_paths, mustWork = FALSE))
    bn <- tolower(basename(tabular_paths))
    tabular_paths <- tabular_paths[!grepl("_resolved\\.|feedback|tracking|ieduplicates", bn)]

    summarize_tabular <- function(path) {
        ext <- tolower(tools::file_ext(path))
        info <- list(path = path, ext = ext, size_bytes = file.info(path)$size,
                    nrow = NA, ncol = NA, sheets = character(), error = NULL)
        tryCatch({
        if (ext == "dta") {
            full <- haven::read_dta(path)
            info$nrow <- nrow(full)
            info$ncol <- ncol(full)
        } else if (ext == "csv") {
            full <- readr::read_csv(path, show_col_types = FALSE, guess_max = 1000)
            info$nrow <- nrow(full)
            info$ncol <- ncol(full)
        } else {
            if (requireNamespace("readxl", quietly = TRUE)) {
            info$sheets <- tryCatch(readxl::excel_sheets(path), error = function(e) character())
            }
            full <- readxl::read_excel(path, n_max = 5)
            info$ncol <- ncol(full)
        }
        }, error = function(e) info$error <<- conditionMessage(e))
        info
    }
    tabular_candidates <- lapply(tabular_paths, summarize_tabular)
    names(tabular_candidates) <- tabular_paths

    # A pre-analysis plan / project description document, or the survey
    # instrument itself if it isn't one of the tabular candidates above —
    # background/content reading only, classified by the agent, never a data
    # source.
    doc_candidates <- list.files(
        input_data_dir, pattern = "\\.(pdf|docx?|txt|md)$", full.names = TRUE,
        ignore.case = TRUE, recursive = TRUE
    )
    doc_candidates <- unique(normalizePath(doc_candidates, mustWork = FALSE))

    list(
        input_data_dir = input_data_dir,
        tabular_candidates = tabular_candidates,
        doc_candidates = doc_candidates,
        status = if (length(tabular_candidates)) "found" else "missing_data"
    )
}

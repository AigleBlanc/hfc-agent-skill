# Plain-text dump of every sheet in a survey instrument workbook (survey,
# choices, settings), not just the first one.
# Usage:
#   Rscript form_text.R <path-to-xlsx> [out-path]
#   source(); out_path <- form_to_text(path)

# Caps rows shown per sheet; the header still states the true row count.
FORM_TEXT_MAX_ROWS <- 300L

form_to_text <- function(path, out_path = NULL) {
    stopifnot(file.exists(path))
    if (!requireNamespace("readxl", quietly = TRUE)) {
        stop("readxl package required to read: ", path)
    }
    sheets <- readxl::excel_sheets(path)
    blocks <- vapply(sheets, function(sh) {
        dat <- tryCatch(
        as.data.frame(readxl::read_excel(path, sheet = sh, col_types = "text"), stringsAsFactors = FALSE),
        error = function(e) NULL
        )
        if (is.null(dat)) {
        return(sprintf("=== SHEET: %s (could not be read) ===\n", sh))
        }
        if (!nrow(dat) || !ncol(dat)) {
        return(sprintf("=== SHEET: %s (0 rows) ===\n", sh))
        }
        clean_cell <- function(x) {
        x[is.na(x)] <- ""
        gsub("\\s+", " ", trimws(x))
        }
        dat[] <- lapply(dat, clean_cell)
        n_show <- min(nrow(dat), FORM_TEXT_MAX_ROWS)
        header <- paste(names(dat), collapse = " | ")
        rows <- apply(dat[seq_len(n_show), , drop = FALSE], 1, paste, collapse = " | ")
        note <- if (nrow(dat) > n_show) {
        sprintf("\n... %d more rows truncated ...", nrow(dat) - n_show)
        } else ""
        sprintf(
        "=== SHEET: %s (%d rows x %d cols) ===\n%s\n%s%s\n",
        sh, nrow(dat), ncol(dat), header, paste(rows, collapse = "\n"), note
        )
    }, character(1))

    text <- paste(blocks, collapse = "\n")
    if (is.null(out_path)) {
        out_path <- file.path(tempdir(), paste0(tools::file_path_sans_ext(basename(path)), "_allsheets.txt"))
    }
    writeLines(text, out_path)
    out_path
}

cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd_args, value = TRUE)
is_main <- length(file_arg) > 0 && grepl("form_text\\.R$", file_arg[[1]])

if (is_main) {
    args <- commandArgs(trailingOnly = TRUE)
    if (!length(args)) stop("Usage: Rscript form_text.R <path-to-xlsx> [out-path]")
    suppressPackageStartupMessages({
        if (requireNamespace("readxl", quietly = TRUE)) library(readxl)
    })
    out <- form_to_text(args[[1]], out_path = if (length(args) > 1) args[[2]] else NULL)
    cat(out, "\n")
}

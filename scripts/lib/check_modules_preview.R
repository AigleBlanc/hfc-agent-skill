# Writes hfc/config/modules.yaml — commented and directly editable — so
# you can review and hand-edit exactly what each check does before
# confirming.

# Wraps `text` into "# "-prefixed lines no wider than `width`.
.wrap_comment <- function(text, width = 78) {
    words <- strsplit(text, "\\s+")[[1]]
    lines <- character()
    cur <- ""
    for (w in words) {
        cand <- if (nzchar(cur)) paste(cur, w) else w
        if (nchar(cand) > width && nzchar(cur)) {
            lines <- c(lines, cur)
            cur <- w
        } else {
            cur <- cand
        }
    }
    if (nzchar(cur)) lines <- c(lines, cur)
    paste0("# ", lines)
}

# TRUE for NULL/NA/empty-string/zero-length values only -- FALSE and 0 are
# real, meaningful settings (e.g. "on: no"), never treated as blank.
.is_blank_yaml_val <- function(x) {
    if (is.null(x) || length(x) == 0) return(TRUE)
    if (length(x) == 1) {
        if (is.na(x)) return(TRUE)
        if (is.character(x) && !nzchar(trimws(x))) return(TRUE)
    }
    FALSE
}

#' Merges a hand-edited/partially-filled modules.yaml (`prefilled`) on top
#' of freshly-guessed defaults (`guessed`), field by field: anything you
#' already set wins, everything else falls back to the guess.
merge_prefilled_modules <- function(guessed, prefilled) {
    codes <- union(names(guessed), names(prefilled))
    stats::setNames(lapply(codes, function(code) {
        g <- guessed[[code]] %||% list()
        p <- prefilled[[code]] %||% list()
        fields <- setdiff(union(names(g), names(p)), "desc")
        merged <- lapply(fields, function(f) {
            pv <- p[[f]]
            if (!.is_blank_yaml_val(pv)) pv else g[[f]]
        })
        names(merged) <- fields
        merged
    }), codes)
}

write_commented_modules_yaml <- function(modules, modules_path) {
    dir.create(dirname(modules_path), recursive = TRUE, showWarnings = FALSE)

    header <- c(
        "# HFC Agent Skill check-module configuration",
        "#",
        "# Controls which data-quality checks run and how they're tuned. Each",
        "# module below (M1-M14) has a short description of what it does, then",
        "# its settings.",
        "#",
        "# - To turn a check off entirely: change its \"on: yes\" to \"on: no\".",
        "# - To change a threshold or variable list: edit the value directly.",
        "# - Save the file when you're done — changes take effect the next time",
        "#   the report is built or rebuilt.",
        ""
    )

    blocks <- lapply(MODULE_ORDER, function(code) {
        m <- modules[[code]] %||% list()
        label <- module_label(code)
        desc <- module_desc(code, modules)
        comment_lines <- .wrap_comment(sprintf("%s — %s: %s", code, label, desc))
        m_with_desc <- c(list(desc = label), m)
        yaml_block <- strsplit(yaml::as.yaml(setNames(list(m_with_desc), code)), "\n")[[1]]
        c(comment_lines, yaml_block, "")
    })

    lines <- c(header, unlist(blocks, use.names = FALSE))
    writeLines(lines, modules_path)
    invisible(normalizePath(modules_path))
}

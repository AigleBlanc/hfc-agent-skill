# Checks a built DETAILED HTML report (detailed/<MMDD>_HFCs_detailed.html)
# against report_sections.json — a quality check, doesn't block the build.
# The condensed parent report is not validated (it holds only the message and
# three trimmed sections).

suppressPackageStartupMessages({
    if (!requireNamespace("xml2", quietly = TRUE)) {
        stop("scripts/lib/report_contract.R requires the 'xml2' package.")
    }
})

REPORT_CONTRACT_FIXED_IDS <- c(About = "about", Summary = "summary", `All Issues` = "all")

#' Reads report_sections.json's section list.
read_report_sections_spec <- function(report_sections_path) {
    if (!file.exists(report_sections_path)) {
        return(list(ok = FALSE, error = paste("report_sections.json not found at", report_sections_path)))
    }
    spec <- tryCatch(jsonlite::fromJSON(report_sections_path, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(spec) || is.null(spec$sections)) {
        return(list(ok = FALSE, error = "report_sections.json did not parse into the expected {notes, sections} shape."))
    }
    list(ok = TRUE, sections = spec$sections)
}

#' Checks the report has every expected section and passes a set of
#' targeted spot-checks. Returns list(ok, missing, unexpected, warnings).
validate_report_contract <- function(html_path, report_sections_path, modules_present, modules = NULL) {
    missing <- character(); unexpected <- character(); warnings <- character()

    if (!file.exists(html_path)) {
        return(list(ok = FALSE, missing = "(html file not found)", unexpected = character(), warnings = character()))
    }
    spec <- read_report_sections_spec(report_sections_path)
    if (!isTRUE(spec$ok)) {
        return(list(ok = FALSE, missing = character(), unexpected = character(), warnings = spec$error))
    }

    doc <- tryCatch(xml2::read_html(html_path), error = function(e) NULL)
    if (is.null(doc)) {
        return(list(ok = FALSE, missing = "(HTML did not parse)", unexpected = character(), warnings = character()))
    }
    has_id <- function(id) length(xml2::xml_find_all(doc, sprintf("//*[@id='%s']", id))) > 0
    section_text <- function(id) {
        nodes <- xml2::xml_find_all(doc, sprintf("//*[@id='%s']", id))
        if (!length(nodes)) return(NA_character_)
        paste(xml2::xml_text(nodes), collapse = " ")
    }

    # Fixed, always-expected sections.
    for (nm in names(REPORT_CONTRACT_FIXED_IDS)) {
        if (!has_id(REPORT_CONTRACT_FIXED_IDS[[nm]])) missing <- c(missing, nm)
    }

    # Every currently-"on"/present module gets its own section.
    for (mod in modules_present) {
        aid <- paste0("mod-", tolower(mod))
        if (!has_id(aid)) missing <- c(missing, sprintf("%s (%s)", module_label(mod), mod))
    }
    # M9 Field Request always brings its adjacent "Other" section with it.
    if ("M9" %in% modules_present && !has_id("mod-other")) missing <- c(missing, "Other")

    # ---- targeted spot-checks ----

    # Field Request's table reads "Info," not "Issue," in its header row.
    if ("M9" %in% modules_present && has_id("mod-m9")) {
        node <- xml2::xml_find_first(doc, "//*[@id='mod-m9']")
        th_texts <- trimws(xml2::xml_text(xml2::xml_find_all(node, ".//th")))
        if (!"Info" %in% th_texts) {
        warnings <- c(warnings, "M9 Field Request: expected an 'Info' column header, not found.")
        }
    }

    # Balance Tables render via gt — its fingerprint class should be present.
    if ("M12" %in% modules_present && has_id("mod-m12")) {
        node <- xml2::xml_find_first(doc, "//*[@id='mod-m12']")
        html_frag <- as.character(xml2::xml_find_all(node, ".//table"))
        if (!any(grepl("gt_table", html_frag, fixed = TRUE))) {
        warnings <- c(warnings, "M12 Balance Tables: expected gt-rendered table(s) (class 'gt_table'), not found.")
        }
    }

    # GPS Map: a map div, or an explicit no-GPS note — either is fine, an
    # empty section is not.
    if ("M10" %in% modules_present && has_id("mod-m10")) {
        txt <- section_text("mod-m10")
        if (!has_id("gps-map") && (is.na(txt) || !grepl("No GPS coordinates", txt, fixed = TRUE))) {
        warnings <- c(warnings, "M10 GPS Map: expected either a map div or a 'No GPS coordinates' note, found neither.")
        }
    }

    # Duplicates (M2): one row per duplicate group with a Value column
    # (submission timestamps), never a Date/Enumerator column.
    if ("M2" %in% modules_present && has_id("mod-m2")) {
        node <- xml2::xml_find_first(doc, "//*[@id='mod-m2']")
        th_texts <- trimws(xml2::xml_text(xml2::xml_find_all(node, ".//th")))
        if (!"Value" %in% th_texts) {
        warnings <- c(warnings, "M2 Duplicates: expected a 'Value' column (submission timestamps), not found.")
        }
        if ("Date" %in% th_texts || "Enumerator" %in% th_texts) {
        warnings <- c(warnings, "M2 Duplicates: found a Date/Enumerator column — should be a pure entity-level aggregate (one row per duplicate group).")
        }
    }

    # M1 never shows a "Last Active Day" table — that table doesn't exist.
    if ("M1" %in% modules_present && has_id("mod-m1")) {
        txt <- section_text("mod-m1")
        if (!is.na(txt) && grepl("Last Active Day", txt, fixed = TRUE)) {
        warnings <- c(warnings, "M1 Completion: found a 'Last Active Day' column — this table shouldn't exist.")
        }
    }

    # 'enum-issues' per-enumerator panels are an All Issues-only feature.
    enum_issue_nodes <- xml2::xml_find_all(doc, "//*[contains(@class,'enum-issues')]")
    if (length(enum_issue_nodes)) {
        outside_all <- Filter(function(n) {
        anc <- xml2::xml_find_first(n, "ancestor::*[@id='all']")
        length(anc) == 0 || is.na(xml2::xml_attr(anc, "id"))
        }, enum_issue_nodes)
        if (length(outside_all)) {
        warnings <- c(warnings, "Found 'enum-issues' per-enumerator panel(s) outside the All Issues section — per-module collapsing should have been removed.")
        }
    }

    # M1's tables always carry Submitted / Completed / Completion headers, and
    # "Submitted (Primary Sample)" whenever a primary sample is known (a roster,
    # or a primary/secondary column).
    if (!is.null(modules) && has_id("mod-m1")) {
        node <- xml2::xml_find_first(doc, "//*[@id='mod-m1']")
        th_texts <- trimws(xml2::xml_text(xml2::xml_find_all(node, ".//th")))
        for (h in c("Submitted", "Completed", "Completion")) {
        if (!h %in% th_texts) warnings <- c(warnings, sprintf("M1 Completion: expected a '%s' column header, not found.", h))
        }
        primary_known <- identical(modules$M1$completion_signal, "roster") ||
        !is.na(modules$M1$replacement_status_col %||% NA_character_)
        if (primary_known && !"Submitted (Primary Sample)" %in% th_texts) {
        warnings <- c(warnings, "M1 Completion: a primary sample is known, expected a 'Submitted (Primary Sample)' column header, not found.")
        }
    }

    list(
        ok = length(missing) == 0 && length(warnings) == 0,
        missing = missing, unexpected = unexpected, warnings = warnings
    )
}

#' One-block human-readable summary.
format_report_contract <- function(v) {
    if (isTRUE(v$ok)) return("Report contract: OK — every expected section present, spot-checks passed.")
    lines <- character()
    if (length(v$missing)) lines <- c(lines, paste0("Missing sections: ", paste(v$missing, collapse = ", ")))
    if (length(v$warnings)) lines <- c(lines, paste0("Warnings: ", paste(v$warnings, collapse = " | ")))
    paste0("Report contract: ISSUES FOUND\n  ", paste(lines, collapse = "\n  "))
}

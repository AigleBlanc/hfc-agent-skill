# Example custom check for a Field Request. Export run_<name>(ds, roles)
# returning a findings tibble (same columns as empty_findings()/mk_findings()).
# Register in hfc/config/modules.yaml under M9, and describe it in
# hfc/config/module_notes.yaml so the report can show it.

run_example_check <- function(ds, roles) {
  # Illustrative only: respondents in study arm A missing an expected
  # benefit/treatment-received flag. Adapt column names and logic to the
  # actual survey.
  group_col <- grep("group|arm|treatment", names(ds), ignore.case = TRUE, value = TRUE)[1]
  received_col <- grep("received|completed|benefit", names(ds), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(group_col) || is.na(received_col)) return(empty_findings())

  tmp <- ds[
    grepl("A|^1$", as.character(ds[[group_col]]), ignore.case = TRUE) &
      (is.na(ds[[received_col]]) | as.character(ds[[received_col]]) %in% c("0", "No", "no", "")),
    ,
    drop = FALSE
  ]
  if (!nrow(tmp)) return(empty_findings())
  mk_findings(tmp, "example_check", "M9", "field_request",
              "Group A respondent missing expected benefit/treatment-received flag", roles, received_col)
}

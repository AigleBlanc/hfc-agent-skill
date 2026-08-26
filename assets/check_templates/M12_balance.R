# M12 (Balance Tables) check, standalone — same four tables as the report,
# printed as plain data frames instead of gt HTML. Descriptive only, never
# produces findings.
# Usage: Rscript hfc/code/checks/M12_balance.R

# Filled in automatically — leave as-is unless running this by hand.
skill <- "your/path/to/hfc-agent-skill/"
code_output_dir <- "your/path/to/hfc/output/"

# Swaps a table's internal-safe column names (e.g. "..grp1..") for the real
# group labels `bt_completed_interviews_tbl()` attaches as bt_col_labels,
# same relabeling `bt_gt_simple()` does for the report's gt version. No other
# module template needs a helper like this — M12 alone renders its report
# tables through gt's own column-relabeling, so this is the one place a
# plain-data-frame standalone script has to reproduce that step by hand.
.bt_print_labeled <- function(df) {
  lbl <- attr(df, "bt_col_labels")
  if (!is.null(lbl)) names(df)[match(names(lbl), names(df))] <- unname(lbl)
  print(as.data.frame(df))
}

run_m12_balance_check <- function() {
  lib <- file.path(skill, "scripts", "lib")
  for (f in c("utils.R", "geo_timezone.R", "media.R", "form_logic.R", "profile_roles.R", "run_checks.R", "sync_fpaths.R", "balance_tables.R")) {
    source(file.path(lib, f))
  }
  suppressPackageStartupMessages({ library(dplyr); library(yaml) })

  cfg <- load_hfc_config(skill)
  if (!isTRUE(cfg$found)) stop("skills/hfc-agent-skill/config.json is not fully configured. Reason: ", cfg$reason)

  roles <- yaml::read_yaml(hfc_path(code_output_dir, "config", "role_map.yaml"))
  modules <- yaml::read_yaml(hfc_path(code_output_dir, "config", "modules.yaml"))
  proj_yaml <- yaml::read_yaml(hfc_path(code_output_dir, "project.yaml"))
  ds <- load_latest_dataset(cfg$input_data_dir, cfg$onedrive_output_dir, proj_yaml$data_file)
  ds <- prepare_ds_for_checks(ds, roles, code_output_dir, modules = modules)
  ds <- ds_for_module_selection(ds, "M12", modules)

  groupings <- modules$M12$groupings %||% list()
  if (!length(groupings)) {
    message("M12 (Balance Tables): on, but no groupings are configured yet.")
    return(invisible(NULL))
  }

  cf <- compute_completion_flag(ds, roles, modules)
  target_ds <- attr(ds, "hfc_target_ds")

  for (i in seq_along(groupings)) {
    g <- groupings[[i]]
    group_col <- g$group_col %||% NA_character_
    group_label <- g$group_label %||% group_col %||% sprintf("Grouping %d", i)
    if (is.na(group_col)) next
    message("\n=== Balance Tables — ", group_label, " ===")

    tbl1 <- bt_completed_interviews_tbl(ds, cf, group_col, group_label)
    if (!is.null(tbl1)) {
      message("-- Completed interviews by ", tolower(group_label), " --")
      .bt_print_labeled(tbl1)
    } else message("(completed-interviews table skipped — fewer than 2 group values)")

    tbl2 <- bt_balance_tbl(ds, roles, cf, group_col, g$covariates %||% character())
    if (!is.null(tbl2)) {
      message("-- Covariate balance by ", tolower(group_label), " --")
      df2 <- tbl2$df
      if ("P value" %in% names(df2)) df2[["P value"]] <- vapply(df2[["P value"]], bt_format_pval, character(1))
      print(as.data.frame(df2))
    } else message("(balance table skipped — no covariates configured, or fewer than 2 group values)")

    tbl3 <- bt_completion_regression_tbl(ds, roles, cf, group_col, group_label, g$other_group_col %||% NA_character_)
    if (!is.null(tbl3)) {
      message("-- Completion regression by ", tolower(group_label), " --")
      df3 <- tbl3$df
      if ("P value" %in% names(df3)) df3[["P value"]] <- vapply(df3[["P value"]], bt_format_pval, character(1))
      print(as.data.frame(df3))
      message(tbl3$source_note)
    } else message("(completion regression skipped — missing cluster column, packages, or not enough data)")

    tbl4 <- bt_replacements_tbl(ds, roles, modules, target_ds, cf, group_col, group_label,
                                 g$roster_group_col %||% NA_character_, g$roster_value_map %||% NULL)
    if (!is.null(tbl4)) {
      message("-- Replacements by ", tolower(group_label), " --")
      print(as.data.frame(tbl4))
    } else message("(replacements table skipped — not configured, no roster loaded, or not enough data)")
  }
}

.args <- commandArgs(trailingOnly = FALSE)
.file <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
if (length(.file) && grepl("M12_balance\\.R$", .file[[1]])) run_m12_balance_check()

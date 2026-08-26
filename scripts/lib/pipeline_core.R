# Runs the checks and writes the output files.
run_checks_and_write_issues <- function(code_output_dir, ds, roles, modules, skill_dir, target_ds = NULL) {
    message("Running checks...")
    check_res <- run_check_modules(ds, roles, modules, code_output_dir = code_output_dir, target_ds = target_ds)
    findings <- check_res$findings
    stats <- check_res$stats
    message("Findings: ", nrow(findings))

    readr::write_csv(findings, hfc_path(code_output_dir, "outputs", "issues.csv"))
    write_check_scripts(code_output_dir, modules, skill_dir = skill_dir)
    write_main_r(code_output_dir, skill_dir = skill_dir)

    list(findings = findings, stats = stats)
}

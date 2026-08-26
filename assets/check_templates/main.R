# Runs every module check currently in this folder, one call — not a copy
# of their logic, just sourcing each and calling the function it defines.
# Usage: Rscript hfc/code/checks/main.R
#
# Each M<N>_*.R file must define a run_m<n>_..._check() function (derived
# from its own filename below) to be picked up — every M1-M14 template
# follows this convention. There's no M9_*.R file: M9 is the custom-check
# slot, agent-authored per project, see custom_check_example.R.

# Filled in automatically — leave as-is unless running this by hand.
skill <- "your/path/to/hfc-agent-skill/"
code_output_dir <- "your/path/to/hfc/output/"

checks_dir <- file.path(code_output_dir, "hfc", "code", "checks")
files <- list.files(checks_dir, pattern = "^M[0-9]+_.*\\.R$", full.names = TRUE)
files <- files[order(as.integer(sub("^M([0-9]+)_.*$", "\\1", basename(files))))]

for (f in files) {
  fn_name <- paste0("run_", tolower(sub("\\.R$", "", basename(f))), "_check")
  message("\n==== ", basename(f), " ====")
  tryCatch({
    source(f)
    if (exists(fn_name, mode = "function")) get(fn_name)() else warning("No '", fn_name, "' in ", f)
  }, error = function(e) message("FAILED: ", conditionMessage(e)))
}

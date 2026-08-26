# Reads config.json's four configured directories, and copies the built
# report into the shared OneDrive folder.

# Falls back to a best guess for the skill's own location.
skill_dir_guess <- function() {
    cands <- c(".claude/skills/hfc-agent-skill", "hfc-agent-skill", ".")
    for (c in cands) {
        if (dir.exists(c) && file.exists(file.path(c, "scripts", "lib", "sync_fpaths.R"))) {
        return(normalizePath(c))
        }
    }
    NA_character_
}

CONFIG_PLACEHOLDER_RE <- "^<.*>$"

.is_unset <- function(x) {
    is.null(x) || !nzchar(as.character(x)) || grepl(CONFIG_PLACEHOLDER_RE, as.character(x))
}

# Loads and validates config.json. Input Data Directory, HFC Output
# Directory, and Code Output Directory are required; Media Folder Directory
# is optional.
CONFIG_JSON_KEYS <- c(
    input_data_dir = "Input Data Directory",
    media_dir = "Media Folder Directory",
    onedrive_output_dir = "HFC Output Directory",
    code_output_dir = "Code Output Directory",
    main_file = "Main Tracking Filename"
)

load_hfc_config <- function(skill_dir = NULL) {
    if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess()
    empty <- function(path = NA_character_, reason = NULL) {
        list(
            found = FALSE, path = path,
            input_data_dir = NA_character_, media_dir = NA_character_,
            onedrive_output_dir = NA_character_, code_output_dir = NA_character_,
            main_file = NA_character_, reason = reason
        )
    }
    if (is.null(skill_dir) || is.na(skill_dir)) return(empty(reason = "missing_config_json"))
    cfg_path <- file.path(skill_dir, "config.json")
    if (!file.exists(cfg_path)) return(empty(reason = "missing_config_json"))

    raw <- tryCatch(jsonlite::fromJSON(cfg_path), error = function(e) NULL)
    if (is.null(raw)) return(empty(path = normalizePath(cfg_path), reason = "invalid_config_json"))

    required <- c("input_data_dir", "onedrive_output_dir", "code_output_dir")
    for (field in required) {
        if (.is_unset(raw[[CONFIG_JSON_KEYS[[field]]]])) {
        return(empty(path = normalizePath(cfg_path), reason = paste0("missing_", field)))
        }
    }

    list(
        found = TRUE,
        path = normalizePath(cfg_path),
        input_data_dir = as.character(raw[[CONFIG_JSON_KEYS[["input_data_dir"]]]]),
        media_dir = if (!.is_unset(raw[[CONFIG_JSON_KEYS[["media_dir"]]]])) as.character(raw[[CONFIG_JSON_KEYS[["media_dir"]]]]) else NA_character_,
        onedrive_output_dir = as.character(raw[[CONFIG_JSON_KEYS[["onedrive_output_dir"]]]]),
        code_output_dir = as.character(raw[[CONFIG_JSON_KEYS[["code_output_dir"]]]]),
        main_file = if (!.is_unset(raw[[CONFIG_JSON_KEYS[["main_file"]]]])) as.character(raw[[CONFIG_JSON_KEYS[["main_file"]]]]) else "issue_tracking.xlsx"
    )
}

# Creates `path` (and any missing parents) if it doesn't exist yet.
ensure_local_folder <- function(path) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    path
}

# Copies the built HTML report into the shared OneDrive folder.
copy_report_to_sync_folder <- function(project_id, skill_dir = NULL, html_path) {
    out <- list(status = "skipped", reason = "no_config", dest_path = NA_character_)
    if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess()
    cfg <- load_hfc_config(skill_dir)
    if (!isTRUE(cfg$found)) {
        out$reason <- cfg$reason %||% "missing_config_json"
        return(out)
    }
    if (!file.exists(html_path)) {
        out$reason <- "html_report_missing"
        return(out)
    }
    tryCatch({
        ensure_local_folder(cfg$onedrive_output_dir)
        dest_name <- basename(html_path)
        dest_path <- file.path(cfg$onedrive_output_dir, dest_name)
        ok <- file.copy(html_path, dest_path, overwrite = TRUE)
        if (isTRUE(ok)) {
            out$status <- "ok"
            out$reason <- "copied"
            out$dest_path <- dest_path
        } else {
            out$reason <- "copy_failed"
        }
    }, error = function(e) {
        out$status <<- "skipped"
        out$reason <<- conditionMessage(e)
    })
    out
}

# Writes hfc/structure.html — a tree map of the configured folders, for you
# to review before the full build runs.

write_product_structure_html <- function(cfg, open = FALSE) {
  hfc <- hfc_root(cfg$code_output_dir)
  dir.create(hfc, recursive = TRUE, showWarnings = FALSE)
  html_path <- file.path(hfc, "structure.html")
  proj_name <- derive_project_id(cfg$input_data_dir)
  media_line <- if (!is.na(cfg$media_dir) && nzchar(cfg$media_dir)) cfg$media_dir else "(not configured)"

  html <- paste0(
'<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>HFC Agent Skill — product structure (', proj_name, ')</title>
  <style>
    :root {
      --bg: #0f1419;
      --panel: #1a222c;
      --line: #2d3a47;
      --text: #e7eef5;
      --muted: #8b9aab;
      --accent: #3d9a7a;
      --accent2: #c4a35a;
      --dir: #6eb5ff;
      --file: #d4dde6;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "IBM Plex Sans", "Source Sans 3", "Segoe UI", sans-serif;
      background:
        radial-gradient(1200px 600px at 10% -10%, #1c3340 0%, transparent 55%),
        radial-gradient(900px 500px at 100% 0%, #2a2418 0%, transparent 50%),
        var(--bg);
      color: var(--text);
      line-height: 1.45;
    }
    main { max-width: 920px; margin: 0 auto; padding: 2.5rem 1.5rem 4rem; }
    h1 {
      font-family: "IBM Plex Serif", Georgia, serif;
      font-weight: 600;
      font-size: clamp(1.6rem, 3vw, 2.1rem);
      margin: 0 0 0.4rem;
    }
    .lede { color: var(--muted); max-width: 40rem; margin: 0 0 1.75rem; }
    .tree {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 1.25rem 1.35rem 1.4rem;
      font-family: "IBM Plex Mono", ui-monospace, monospace;
      font-size: 0.86rem;
      overflow-x: auto;
    }
    ul.tree-root, ul.tree-root ul { list-style: none; margin: 0; padding-left: 1.15rem; }
    ul.tree-root { padding-left: 0; }
    li { position: relative; padding: 0.18rem 0; color: var(--file); }
    .dir > .name { color: var(--dir); font-weight: 500; }
    .meta { color: var(--muted); font-size: 0.8rem; margin-left: 0.5rem; }
    footer { margin-top: 2rem; font-size: 0.85rem; color: var(--muted); }
  </style>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Serif:wght@600&display=swap" rel="stylesheet" />
</head>
<body>
  <main>
    <h1>HFC Agent Skill product — ', proj_name, '</h1>
    <p class="lede">Built artifacts for this survey live under <code>hfc/</code>, inside your configured code output directory — decoupled from wherever the raw data actually lives. Raw microdata is read in place and never copied. The shared <code>issue_tracking.xlsx</code> and its dated snapshot/resolutions subfolders live entirely in your configured OneDrive folder, not shown in this local tree.</p>
    <div class="tree" aria-label="Configured directories">
      <ul class="tree-root">
        <li class="dir"><span class="name">Input data directory</span><span class="meta">', cfg$input_data_dir, ' — read in place, never copied</span></li>
        <li class="dir"><span class="name">Media directory</span><span class="meta">', media_line, '</span></li>
        <li class="dir"><span class="name">HFC output directory</span><span class="meta">', cfg$onedrive_output_dir, ' — issue_tracking.xlsx + snapshots</span></li>
        <li class="dir"><span class="name">Code output directory</span><span class="meta">', cfg$code_output_dir, '</span>
          <ul>
            <li class="dir"><span class="name">hfc/</span>
              <ul>
                <li><span class="name">structure.html</span><span class="meta">this map</span></li>
                <li><span class="name">project.yaml</span></li>
                <li class="dir"><span class="name">config/</span>
                  <ul>
                    <li>modules.yaml · role_map.yaml</li>
                    <li>config.json</li>
                  </ul>
                </li>
                <li class="dir"><span class="name">instruments/</span><span class="meta">optional form copy</span></li>
                <li class="dir"><span class="name">outputs/</span><span class="meta">&lt;MMDD&gt;_HFCs.html (condensed daily update, dated per build) · issues.csv · detailed/&lt;MMDD&gt;_HFCs_detailed.html (full report)</span></li>
                <li class="dir"><span class="name">code/</span><span class="meta">main.R</span>
                  <ul>
                    <li class="dir"><span class="name">checks/</span><span class="meta">M1–M14 (runnable) + custom (e.g. example_check.R)</span></li>
                    <li class="dir"><span class="name">resolutions/</span><span class="meta">post-feedback fix scripts</span></li>
                  </ul>
                </li>
              </ul>
            </li>
          </ul>
        </li>
      </ul>
    </div>
    <footer>HFC Agent Skill · code output structure</footer>
  </main>
</body>
</html>
')
  writeLines(html, html_path)

  if (isTRUE(open) && !identical(Sys.getenv("CI"), "true") &&
      !identical(Sys.getenv("HFC_NO_OPEN"), "1")) {
    try(utils::browseURL(html_path), silent = TRUE)
  }
  normalizePath(html_path)
}

# Documentation Implementation Plan
## PlatyPS + MkDocs Material + GitHub Pages

This document is an implementation guide intended for use with Claude Code.
Work through each phase in order. Do not skip phases.

---

## Context and Decisions

The following decisions have already been made and must not be revisited:

| Decision | Choice |
|---|---|
| PlatyPS markdown location | `docs/commands/` |
| MAML XML (Get-Help) | CI-only — generated during Actions, never committed |
| MkDocs navigation | Auto-generated via `mkdocs-awesome-pages-plugin` |
| Publish trigger | Merge to `main` only (push trigger) |
| Hosting | GitHub Pages on personal private repo (requires GitHub Pro) |

---

## Toolchain Overview

- **PlatyPS (`Microsoft.PowerShell.PlatyPS`)** — reflects against the loaded module to generate
  Markdown stubs, and converts those Markdown files to MAML XML for `Get-Help`
- **MkDocs Material** — Python static site generator that renders the Markdown into a
  hosted documentation website
- **mkdocs-awesome-pages-plugin** — auto-generates site navigation from folder structure;
  eliminates the need to manually maintain the `nav:` block in `mkdocs.yml`
- **GitHub Actions** — runs the full build (MAML export + site build) and deploys to GitHub Pages on every merge to `main`

The Markdown files in `docs/commands/` are the **single source of truth** for both outputs.

---

## Phase 1 — Identify Module Structure

Before creating any files, identify these two values. They are used as placeholders
throughout the rest of this plan:

- `<ModuleName>` — the base name of the `.psd1` file (e.g. `MyModule`)
- `<ModuleRoot>` — the relative path from the repo root to the folder containing the `.psd1`
  (e.g. `src/MyModule` or just `MyModule`)

Run the following to locate them:

```powershell
Get-ChildItem -Recurse -Include *.psd1 | Select-Object FullName
```

Do not proceed until both values are confirmed. Substitute them into every file created
in subsequent phases.

---

## Phase 2 — Install Prerequisites

Install PlatyPS locally so stubs can be generated in Phase 3:

```powershell
Install-PSResource -Name Microsoft.PowerShell.PlatyPS -TrustRepository
```

Python and MkDocs do **not** need to be installed locally. The GitHub Actions workflow
handles that. If a local preview is wanted later, `pip install mkdocs-material
mkdocs-awesome-pages-plugin` is sufficient.

---

## Phase 3 — Generate PlatyPS Markdown Stubs

Import the module, then generate the initial Markdown files:

```powershell
Import-Module ./<ModuleRoot>/<ModuleName>.psd1 -Force

$splat = @{
    ModuleInfo     = Get-Module -Name '<ModuleName>'
    OutputFolder   = './docs/commands'
    WithModulePage = $true
}
New-MarkdownCommandHelp @splat
```

Expected output structure after this step:

```
docs/
└── commands/
    └── <ModuleName>/
        ├── <ModuleName>.md        ← module index page
        ├── Get-SomeCommand.md
        └── Set-SomeCommand.md
```

### Important notes on stub content

PlatyPS populates sections by reflecting against the module. Because comment-based help
is already present in this project (written by Claude Code), most sections should be
populated automatically from:

| Comment-based help | PlatyPS section |
|---|---|
| `.SYNOPSIS` | `## SYNOPSIS` |
| `.DESCRIPTION` | `## DESCRIPTION` |
| `.PARAMETER <Name>` | Parameter description block |
| `.EXAMPLE` | `## EXAMPLES` |
| `.OUTPUTS` | `## OUTPUTS` |
| `.NOTES` | `## NOTES` |
| `.LINK` | `## RELATED LINKS` |

Any section that shows `{{ Fill ... }}` was absent from the comment-based help
and must be authored manually. Search all files for `{{ Fill` to find them:

```powershell
Select-String -Path ./docs/commands/<ModuleName>/*.md -Pattern '\{\{ Fill'
```

Resolve all placeholders before proceeding to Phase 4.

### Post-generation fixes

PlatyPS generates three patterns that need correction before the site renders well:

#### 1. Aliases placeholder

Every command file contains a bogus aliases section:

```markdown
## ALIASES

This cmdlet has the following aliases,
  {{Insert list of aliases}}
```

Replace the body with `None.` if the function has no aliases, or list the actual
aliases. Check programmatically:

```powershell
Import-Module ./<ModuleRoot>/<ModuleName>.psd1 -Force
foreach ($cmd in (Get-Command -Module '<ModuleName>')) {
    $aliases = (Get-Alias -Definition $cmd.Name -ErrorAction SilentlyContinue).Name -join ', '
    Write-Host "$($cmd.Name): $(if ($aliases) { $aliases } else { 'None' })"
}
```

#### 2. Examples not fenced as code

PlatyPS emits example code as plain text under `### EXAMPLE N` headings without
fenced code blocks. MkDocs renders them without syntax highlighting. Wrap each
example body in ` ```powershell ` / ` ``` ` fences.

#### 3. Empty INPUTS section

Functions that do not accept pipeline input get an empty `## INPUTS` section.
For each function that has no `ValueFromPipeline = $true` parameters, replace
the empty section with:

```markdown
## INPUTS

None. This cmdlet does not accept pipeline input.
```

Check which functions accept pipeline input:

```powershell
Import-Module ./<ModuleRoot>/<ModuleName>.psd1 -Force
foreach ($cmd in (Get-Command -Module '<ModuleName>')) {
    $pipeParams = (Get-Help $cmd.Name -Full).parameters.parameter.Where({
        $_.pipelineInput -match 'true'
    })
    Write-Host "$($cmd.Name): $(if ($pipeParams) {
        ($pipeParams | ForEach-Object { "$($_.name) ($($_.pipelineInput))" }) -join ', '
    } else { 'None' })"
}
```

---

## Phase 4 — Validate Markdown Structure

Confirm PlatyPS is satisfied with every file before building the site:

```powershell
$files = Measure-PlatyPSMarkdown -Path ./docs/commands/<ModuleName>/*.md
$files.Where({ $_.Filetype -match 'CommandHelp' }) | ForEach-Object {
    Test-MarkdownCommandHelp -Path $_.FilePath
}
```

Resolve any reported structural errors. Do not proceed if errors are present.

---

## Phase 5 — Regenerate the Module Index Page

After all command files are complete, rebuild the module index so it reflects
the authored synopses:

```powershell
Import-Module ./<ModuleRoot>/<ModuleName>.psd1 -Force

Measure-PlatyPSMarkdown -Path ./docs/commands/<ModuleName>/*.md |
    Where-Object Filetype -match 'CommandHelp' |
    Import-MarkdownCommandHelp -Path { $_.FilePath } |
    Update-MarkdownModuleFile -Path ./docs/commands/<ModuleName>/<ModuleName>.md
```

Inspect `docs/commands/<ModuleName>/<ModuleName>.md` and confirm synopses
are populated correctly.

---

## Phase 6 — Create Site Support Files

Create the following files exactly as specified. Substitute `<ModuleName>` and
`<ModuleRoot>` where indicated.

### `docs/index.md`

This is the site home page. Write it manually — it is not generated by PlatyPS.
Minimum required content:

```markdown
# <ModuleName>

One paragraph describing what this module does and who it is for.

## Installation

\```powershell
Install-Module -Name <ModuleName>
\```

## Quick Start

A minimal working example with explanation.
```

### `docs/.pages`

Controls top-level site navigation order for the awesome-pages plugin:

```yaml
nav:
  - index.md
  - commands: commands
```

### `docs/commands/.pages`

Controls ordering of the commands folder:

```yaml
order: asc
```

### `docs/commands/<ModuleName>/.pages`

Controls ordering of command pages within the module folder:

```yaml
order: asc
```

### `mkdocs.yml`

Place at the **repo root**. Substitute `<ModuleName>`:

```yaml
site_name: <ModuleName> Documentation
docs_dir: docs

theme:
  name: material
  features:
    - navigation.sections
    - navigation.top
    - navigation.indexes
    - content.code.copy
    - search.highlight

plugins:
  - search
  - awesome-pages

markdown_extensions:
  - meta
  - admonition
  - pymdownx.highlight:
      anchor_linenums: true
  - pymdownx.superfences
  - tables
  - toc:
      permalink: true
```

> **Note on `meta` extension:** This is required. PlatyPS writes YAML frontmatter into
> every Markdown file. Without `meta`, MkDocs renders that frontmatter as a visible table
> at the top of every page.

### `requirements.txt`

Place at the **repo root**. Before creating this file, check current latest versions:

```powershell
# In a shell with pip available
pip index versions mkdocs-material
pip index versions mkdocs-awesome-pages-plugin
```

Then create the file with pinned versions:

```
mkdocs-material==<latest>
mkdocs-awesome-pages-plugin==<latest>
```

---

## Phase 7 — Create the GitHub Actions Workflow

Create `.github/workflows/docs.yml`. Substitute `<ModuleName>` and `<ModuleRoot>`:

```yaml
name: Publish Docs

on:
  push:
    branches:
      - main

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install PlatyPS
        shell: pwsh
        run: Install-PSResource -Name Microsoft.PowerShell.PlatyPS -TrustRepository

      - name: Export MAML
        shell: pwsh
        run: |
          Import-Module ./<ModuleRoot>/<ModuleName>.psd1 -Force
          New-Item -ItemType Directory -Path ./en-US -Force | Out-Null
          Measure-PlatyPSMarkdown -Path ./docs/commands/<ModuleName>/*.md |
              Where-Object Filetype -match 'CommandHelp' |
              Import-MarkdownCommandHelp -Path { $_.FilePath } |
              Export-MamlCommandHelp -OutputFolder ./en-US -Force

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install MkDocs
        run: pip install -r requirements.txt

      - name: Build site
        run: mkdocs build --strict

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: site/

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

> **Note on PowerShell:** Do not add an `actions/setup-powershell` step — that action
> does not exist. The `ubuntu-latest` runner image ships with PowerShell 7 pre-installed.
> Use `shell: pwsh` on steps that need PowerShell; no setup action is required.

> **Note on `--strict`:** This flag causes the build to fail on warnings such as broken
> internal links or missing referenced pages. This is intentional — it prevents
> documentation debt from accumulating silently.

---

## Phase 8 — Enable GitHub Pages on the Repository

This is a one-time manual step in the GitHub UI. It cannot be done via code.

1. Navigate to the repo on GitHub
2. Go to **Settings** → **Pages**
3. Under **Source**, select **GitHub Actions**
4. Save

No branch pre-creation is needed. The Actions deployment handles everything.

> **Prerequisite:** GitHub Pages on a private repo requires **GitHub Pro**. Confirm this
> before expecting the deployment step to succeed.

---

## Phase 9 — Initial Commit and Verify

Add all new files, commit, and push to `main`:

```powershell
git add .
git commit -m "docs: add PlatyPS markdown, MkDocs config, and Pages workflow"
git push origin main
```

Watch the workflow run under **Actions** → **Publish Docs** in the GitHub UI.
First run takes approximately 2-3 minutes. The deployed site URL will appear in
the workflow summary and at **Settings** → **Pages**.

The site is published at: `https://<github-username>.github.io/<repo-name>/`

---

## Ongoing Workflow — After Module Changes

Run this sequence whenever commands are added or modified:

```powershell
# 1. Sync stubs — adds placeholders for new/changed parameters, conservative about
#    existing content
Import-Module ./<ModuleRoot>/<ModuleName>.psd1 -Force
Update-MarkdownCommandHelp -Path ./docs/commands/<ModuleName> -Force

# 2. Find any new placeholders that need authoring
Select-String -Path ./docs/commands/<ModuleName>/*.md -Pattern '\{\{ Fill'

# 3. Author any new placeholder content, then rebuild the module index
Measure-PlatyPSMarkdown -Path ./docs/commands/<ModuleName>/*.md |
    Where-Object Filetype -match 'CommandHelp' |
    Import-MarkdownCommandHelp -Path { $_.FilePath } |
    Update-MarkdownModuleFile -Path ./docs/commands/<ModuleName>/<ModuleName>.md

# 4. Validate
Measure-PlatyPSMarkdown -Path ./docs/commands/<ModuleName>/*.md |
    Where-Object Filetype -match 'CommandHelp' |
    ForEach-Object { Test-MarkdownCommandHelp -Path $_.FilePath }

# 5. Commit → PR → merge → Actions publishes automatically
```

> **Note on backup files:** `Update-MarkdownCommandHelp` creates `.bak` files alongside
> the originals. Review the diff, then delete the `.bak` files before committing.
> Add `*.bak` to `.gitignore` to prevent accidental commits.

---

## Files Created by This Implementation

```
<repo-root>/
├── .github/
│   └── workflows/
│       └── docs.yml                          ← Actions workflow
├── docs/
│   ├── .pages                                ← awesome-pages top-level nav
│   ├── index.md                              ← site home page (manual)
│   └── commands/
│       ├── .pages                            ← awesome-pages commands order
│       └── <ModuleName>/
│           ├── .pages                        ← awesome-pages command page order
│           ├── <ModuleName>.md               ← module index (PlatyPS)
│           ├── Get-SomeCommand.md            ← command help (PlatyPS)
│           └── Set-SomeCommand.md            ← command help (PlatyPS)
├── mkdocs.yml                                ← MkDocs configuration
└── requirements.txt                          ← Python deps for CI
```

Files intentionally **not** committed:
- `en-US/<ModuleName>-help.xml` — MAML, generated in CI only
- `site/` — MkDocs build output, generated in CI only
- `docs/commands/<ModuleName>/*.bak` — PlatyPS update backups

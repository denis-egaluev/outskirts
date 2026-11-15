---
description: Run outskirts from Visual Studio Code: projects and results in the side bar, diagnostics in the Problems panel, quick fixes, a configuration editor, baselines and scan on save.
---

# Visual Studio Code

The outskirts extension runs the installed `outskirts` from the editor and shows the unused code it finds next to the code itself. It does not analyze Swift on its own: it runs `outskirts scan` in the project directory, so results match those of the command line and [CI](ci.md).

## Install

Install **outskirts** (`tiny-earth-moon.outskirts`) from the Extensions view, from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=tiny-earth-moon.outskirts), or from [Open VSX](https://open-vsx.org/extension/tiny-earth-moon/outskirts) for editors that use it.

The extension needs the outskirts command line tool:

```sh
brew install tiny-earth-moon/tap/outskirts
```

When outskirts is not on the `PATH`, set `outskirts.path` to its location. The **Open Getting Started** command opens a walkthrough of install, first scan, review, configuration, baseline and CI; it also opens once after installation.

## Projects and results

The outskirts icon in the activity bar opens three views.

- **Projects** lists every project of the workspace: the workspace folders and the Swift packages and Xcode projects one level below them. Each row shows its state, with buttons to scan, cancel, clear and edit its configuration. Each project keeps its own results.
- **Results** shows the results of the selected project, grouped by file or by kind with their counts; click a result to open it. **Filter…** keeps only the kinds you pick and the results whose name or path contains a text. The Problems panel keeps every diagnostic.
- **Scan Options** shows the options of the project with their current values: reuse of the index, severity, extra arguments, grouping, agent and the configuration editor.

Results also appear in the Problems panel, with the severity set by `outskirts.severity`, or per kind by `outskirts.severityByKind`.

When a file with results changes after a scan, its results are marked stale and leave the Problems panel, as they may point at the wrong lines. Scan again to refresh them.

When a scan fails, the error stays in the window: **Results** shows it under the project with **Open Output**, **Scan Again** and, when a setting or the configuration file is the cause, **Fix…**; the project row and the status bar say *scan failed*. A notification appears only when the outskirts views are closed.

## Quick fixes

On an outskirts diagnostic, the Quick Fix menu (the lightbulb, `Cmd+.`) adds the [comment command](comment-commands.md) that keeps the code:

- `// outskirts:ignore` above the declaration.
- `// outskirts:ignore:parameters <name>` above the function of an unused parameter.
- `// outskirts:ignore:all` at the top of the file.

## Configuration editor

**Edit Configuration** opens the `.outskirts.yml` of a project as a form. The form is built from `outskirts config schema`, so it lists every [option](configuration.md) of the installed outskirts with its description and default.

- Saving writes only the options that changed, and keeps the comments, the order of the keys and the keys outskirts does not know.
- Recommendations computed from the project, such as `schemes` or `retain_public`, can be applied or dismissed. Without a configuration file, **Create .outskirts.yml** applies them all.
- After saving, the form runs `outskirts config check` and shows the problems it reports.
- **Open as YAML** opens the file itself.

## Baseline

To adopt outskirts in a project that already has results, right-click it in the Projects view and choose **Accept Current Results as Baseline**. The extension records today's results as a [baseline](baselines.md) and offers to add it to `.outskirts.yml`; later scans show only new results. **Clear Baseline** deletes the file after a confirmation.

## Scan on save

With `outskirts.scanOnSave` set to `project`, saving a Swift file rescans its project once saves have stopped for `outskirts.scanOnSaveDelay` milliseconds. A project that was not scanned yet in the session is not scanned on save.

> [!NOTE]
> With `outskirts.skipBuild`, outskirts reads the index of the last build, which saving does not update: results follow the last build, not the saved file, until a scan that builds.

## Fix with Agent

**Fix with Agent** starts a coding agent in a terminal, in the project directory, with a prompt that lists the results and asks it to remove the unused code. Use the button on a project, a file or a single result of the Results view; it sends the results of the last scan, without scanning again.

Claude Code, GitHub Copilot CLI, Codex CLI, Gemini CLI and Cursor Agent are known; a custom command is set with `outskirts.agentCommand`. By default the agent checks each removal by searching the code; `outskirts.agentVerify` lets it build or run tests instead. Review its changes as you would any other, then scan again.

## Settings

`arguments`, `severity`, `severityByKind`, `skipBuild`, `scanOnSave` and `scanOnSaveDelay` can differ per workspace folder; the projects found in one folder share them.

| Setting | Default | Description |
|---------|---------|-------------|
| `outskirts.path` | `outskirts` | Path of the outskirts executable, or its name when it is on the `PATH`. |
| `outskirts.arguments` | `[]` | Extra arguments passed to `outskirts scan`, e.g. `["--schemes", "App"]`. |
| `outskirts.severity` | `warning` | Severity of the diagnostics: `error`, `warning`, `information` or `hint`. |
| `outskirts.severityByKind` | `{}` | Severity per kind of result, overriding `outskirts.severity`; `off` hides the kind from the Problems panel, not from Results. Example: `{ "missingFinal": "hint" }`. |
| `outskirts.groupBy` | `file` | Initial grouping of the Results view: `file` or `kind`. The toggle in the view changes it for the session only. |
| `outskirts.skipBuild` | `false` | Reuse the existing index instead of building the project (`--skip-build`). |
| `outskirts.scanOnSave` | `off` | `project` rescans the project of a saved Swift file. |
| `outskirts.scanOnSaveDelay` | `1500` | Milliseconds to wait after the last save before scanning on save (at least 500). |
| `outskirts.agent` | empty | Agent that Fix with Agent starts: `claude`, `copilot`, `codex`, `gemini`, `cursor` or `custom`. Empty asks. |
| `outskirts.agentCommand` | `[]` | Command of the custom agent: the executable, then its arguments, with `${prompt}` as one whole argument. No shell is used. |
| `outskirts.agentVerify` | `false` | Lets the agent build the project or run its tests after its changes. |

`outskirts.path`, `outskirts.agent`, `outskirts.agentCommand` and `outskirts.agentVerify` are machine-scoped: they appear only in the **User** tab of the Settings editor and are never read from a workspace.

The analysis options, such as `retain_public` or `report_exclude`, are not VS Code settings. They live in `.outskirts.yml`, so that the editor, the command line and CI all analyze the project the same way. Edit them in the [configuration editor](#configuration-editor) or in the file; see [Configuration](configuration.md).

## Changelog

See the [extension changelog](https://github.com/tiny-earth-moon/outskirts-vscode/blob/main/CHANGELOG.md).

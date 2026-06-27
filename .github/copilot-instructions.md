# Powershell Setup - Project Instructions

## Product Context

This repository provides a modular PowerShell profile installer optimized for
interactive terminal use without adding unnecessary startup work to automation,
CI pipelines, or agent sessions.

`Install-PowerShellProfile.ps1` generates a lightweight core profile, an
interactive profile for prompts, completions, and optional modules, and a
`profile-extras.ps1` file for personal commands and quality-of-life helpers.
Network synchronization of extras must remain an explicit manual operation;
profile startup must not perform network requests.

The `info` function in `profile-extras.ps1` is the user-facing command catalog.
In addition to every command defined in that file, the catalog must always
include the core commands `profile-benchmark` and `update-extras`, with usage
examples for both. Installer module availability, defaults, and behavior are
documented in `README.md`.

## Git Commit Message Instructions

Always generate commit messages matching these rules:

- Use the Conventional Commits format: type(scope): description
- Allowed types: feat, fix, docs, style, refactor, perf, test, chore, ci
- Keep the subject line under 50 characters
- Use the imperative mood (e.g., "Add feature" instead of "Added feature")
- Do not end the subject line with a period
- Separate the subject from the body with a blank line
- Use bullet points (\*) in the body section to explain "what" and "why"
- The commit must be written in American English.

Use this format:

```text
<type>(optional-scope): <short imperative summary>
```

Common types:

- `feat`: user-visible feature
- `fix`: bug fix
- `docs`: documentation-only change
- `style`: code style, formatting, whitespace, or linting changes with no functional impact
- `refactor`: behavior-preserving code restructuring
- `perf`: performance improvement without changing external behavior
- `test`: tests only
- `chore`: build/tooling/maintenance
- `ci`: continuous integration and deployment configuration changes

Examples:

```text
feat(module): add git module
fix(auth): update fine-grained token permission template
docs(readme): document feature instructions
```

## Verification

- Whenever a function is created or modified in `profile-extras.ps1`, update
  the `info` function so its command catalog and description remain accurate.
- Whenever a module is added to or removed from
  `Install-PowerShellProfile.ps1`, update `README.md` so the documented module
  inventory and behavior remain accurate.

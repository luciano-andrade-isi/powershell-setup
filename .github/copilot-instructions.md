# Powershell Setup - Project Instructions

## Product Context

TODO

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

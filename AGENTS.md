# Agents Guide — ResiCheck Automation

ResiCheck (1D ERT Field App) welcomes structured contributions from automation agents (GitHub Copilot, Codex, GPT assistants, and similar bots).  
This guide keeps those edits predictable, auditable, and aligned with the workflow used in the Codex CLI harness.

---

## Scope of Agent Changes

✅ Agents may update:
- Flutter source and tests under `lib/` and `test/`.
- Flutter configuration (`pubspec.yaml`, `analysis_options.yaml`).
- Android/iOS Gradle build scripts (`android/`, `ios/`).
- Project documentation (`README.md`, `AGENTS.md`, `docs/`).
- Automation notes or scripts under `scripts/ci/` **only when the task explicitly calls for it**.

❌ Agents must NOT:
- Install Flutter, Android SDKs, or other system-level dependencies.
- Run `flutter doctor`, `flutter pub get`, or similar setup commands (handled outside the agent flow).
- Commit secrets, credentials, API keys, or machine-specific files.
- Modify GitHub Actions or CI workflows without explicit instruction.
- Check in generated artifacts such as `.flutter-plugins-dependencies`, `.dart_tool/`, `buildlogs/last_test.txt`, or platform build outputs.

---

## Branching Conventions

- **Feature branches**: `feat/<description>`
- **Fix branches**: `fix/<description>`
- **Documentation branches**: `docs/<description>`
- **Maintenance branches**: `chore/<description>`

Examples:  
- `fix/android-gradle-conflict`  
- `feat/simulation-mode`  
- `docs/readme-updates`

---

## Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/):  
- `feat: add residual strip visualization`  
- `fix: resolve Kotlin plugin conflict in Gradle`  
- `docs: update emulator setup instructions`  
- `chore: reformat Dart code with dart format`

---

## Pull Request Guidelines

Each PR opened by an agent must:
1. Target the `main` branch.  
2. Contain a clear description:
   - What file(s) were changed.  
   - Why the change was made (include error output if relevant).  
   - How the change was tested (reference `run bash scripts/ci/test_wsl.sh` or the specific sanctioned command output).  
3. Reference the commit message style from above.

---

## Analyzer/Test Loop

- Preferred: `run bash scripts/ci/test_wsl.sh`  
  - Formats via `dart format .`, runs `dart analyze --no-fatal-warnings`, and executes `flutter --no-version-check test -x widget_dialog`.  
  - Writes analyzer/test output to `buildlogs/last_test.txt`; review and summarize key failures instead of pasting entire logs.  
- Individual invocations of `dart format .`, `dart analyze`, or `flutter --no-version-check test -x widget_dialog` are also pre-approved via `.codex/config.toml`.  
- Do not introduce alternative tooling or test runners unless requested.

---

## Example Workflow

1. Developer provides the change request or analyzer/test failures.  
2. Agent inspects the relevant code and proposes a minimal diff.  
3. Run `run bash scripts/ci/test_wsl.sh` (or the approved commands) to format, analyze, and test; summarize results from `buildlogs/last_test.txt`.  
4. Agent commits changes with a Conventional Commit message on a branch such as `fix/<description>`.  
5. Developer reviews the PR and merges when satisfied.  

---

## Notes

- This app is **offline-first** and field-facing—stability over feature creep.  
- Favor defensive fixes and targeted coverage over sweeping refactors.  
- Leave brief explanatory comments when a code change is non-obvious.  
- `.codex/config.toml` mirrors the approved command list; `docs/CODEX_TEST_LOOP.md` expands on the sanctioned WSL loop and expectations around summarizing analyzer/test output.  
- Keep generated artifacts out of commits; re-run the loop after each patch until it exits cleanly.  

---

_This guide ensures that automated contributions remain predictable, traceable, and aligned with THG’s internal workflow._

---

# Agents Guide — 1D ERT Field App (VES QC)

This repository allows structured contributions from automation agents (e.g., GitHub Copilot, Codex, GPT assistants, or other bots).  
The purpose of this guide is to define safe boundaries and conventions for automated edits so the project remains stable and auditable.

---

## Scope of Agent Changes

✅ Agents are permitted to modify:
- Dart/Flutter source (`lib/`, `test/`).
- Flutter configuration (`pubspec.yaml`, `analysis_options.yaml`).
- Android/iOS Gradle build scripts (`android/`, `ios/`).
- Documentation (`README.md`, `AGENTS.md`, `docs/`).

❌ Agents must NOT:
- Install Flutter, Android SDKs, or system-level dependencies.
- Run `flutter doctor`, `flutter pub get`, or similar commands (these are handled locally).
- Commit secrets, credentials, or API keys.
- Modify GitHub Actions or CI workflows without explicit instruction.

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
   - How the change was tested (if applicable).  
3. Reference the commit message style from above.

---

## Example Workflow

1. Developer pastes analyzer/build/test errors into the agent.  
2. Agent proposes a fix and opens a branch `fix/<description>`.  
3. Agent commits changes with a structured message.  
4. Developer reviews the PR and merges when satisfied.  

---

## Notes

- This app is **offline-first** and field-facing. Stability is prioritized over feature creep.  
- Defensive coding and clear test coverage are preferred over aggressive refactoring.  
- Agents should leave explanatory comments in code when applying non-trivial fixes.  
- Local automation helpers: `.codex/config.toml` keeps approvals on while whitelisting the test loop, and `scripts/ci/test_wsl.sh` is the approved formatter/analyzer/test runner (see `docs/CODEX_TEST_LOOP.md`).  

---

_This guide ensures that automated contributions remain predictable, traceable, and aligned with THG’s internal workflow._

---

# Codex ⇄ Test Loop (WSL)

This workflow keeps analyzer and test feedback close to the Codex CLI so fixes can be proposed without leaving the terminal.

## Prerequisites
- Flutter and Dart SDKs are already installed and warmed on the host (run once outside Codex: `flutter --no-version-check --version && flutter precache --linux`).
- The repository is checked out in WSL at `~/code/resicheck`.

## Standard Loop
1. Apply the current PR prompt or patch instructions in Codex.
2. Execute the scripted test pass:
   ```bash
   run bash scripts/ci/test_wsl.sh
   ```
   The script formats sources, runs `dart analyze`, then runs `flutter --no-version-check test -x widget_dialog`. Outputs stream to the terminal and append to `buildlogs/last_test.txt`.
3. Review failures and summarize them for follow-up:
   ```bash
   Open buildlogs/last_test.txt, list the top failure causes, propose minimal diffs, and apply them.
   ```
4. Re-run the test script after each patch. Repeat until the script exits cleanly.
5. Once green, prepare the PR branch, craft a Conventional Commit message, and hand off for review.

## Notes
- The script never touches Flutter caches; it uses `dart` for formatting and analysis and suppresses analytics.
- `buildlogs/last_test.txt` is overwritten on each run, providing a single source of truth for the latest analyzer/test output.
- Command approvals stay enabled through `.codex/config.toml`; expect the first invocation per session to request confirmation.
- Keep prompts concise so Codex maintains enough context (restart the session if context approaches its limit).

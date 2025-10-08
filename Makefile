.PHONY: dev test apk format analyze ci-test codex-prebuild

CI_TEST_CMD = bash scripts/ci_test_unix.sh
ifeq ($(OS),Windows_NT)
CI_TEST_CMD = powershell -ExecutionPolicy Bypass -File scripts/ci_test_windows.ps1
endif

dev: codex-prebuild
	flutter run

test:
	flutter test

format:
	dart format .

analyze:
	flutter analyze

ci-test:
	$(CI_TEST_CMD)

codex-prebuild: ci-test

apk: codex-prebuild
	flutter build apk --release

@ECHO OFF
SETLOCAL
WHERE gradle >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  gradle %*
) ELSE (
  ECHO Gradle is required but was not found in PATH. Install Gradle or generate the wrapper via "flutter create ." >&2
  EXIT /B 1
)

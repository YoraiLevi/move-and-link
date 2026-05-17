# move-and-link — project memory

## Testing policy: CI is the only authoritative test environment

**Do not run the test suite locally and treat the result as proof that a
change works.** The canonical validator is the GitHub Actions workflow at
`.github/workflows/test.yml`. Push to a branch and read the CI matrix
result; that is the source of truth.

### Why this rule exists

Local test runs on a single host can produce **misleadingly green results**
that do not reflect what CI sees. Concrete failure modes observed in this
repo:

- **MSYS bash on Windows handles symlinks differently from real Linux bash.**
  Without `MSYS=winsymlinks:nativestrict`, `ln -s` silently produces file
  copies; with it, symlinks may still require Developer Mode or an elevated
  shell. Neither matches the behavior on `ubuntu-latest`.
- **`[IO.Path]` cross-platform behavior in PowerShell differs between
  Windows and Linux/macOS.** On Windows, `\` is a directory separator and
  `.\foo` normalizes correctly; on Linux/macOS pwsh, `\` is a regular
  filename character and `.\foo` stays unnormalized. Paths that round-trip
  cleanly on Windows pwsh can leak literal `./` or `\` segments into link
  targets on Linux/macOS pwsh. Confirmed instance: commit `96446b9` broke
  9 of 17 pwsh tests on ubuntu-latest and macos-latest while staying
  green on windows-latest.
- **zsh is rarely installed on Windows hosts.** A local Windows dev cannot
  validate the zsh job at all.
- **Filesystem case sensitivity** differs between platforms (case-insensitive
  default on Windows/macOS, case-sensitive on Linux) and can hide bugs that
  CI exposes.

### Required workflow

1. Make the change locally.
2. Commit and push to a branch.
3. Open a PR (or push to the working branch) and wait for the seven-job CI
   matrix to complete:
   - `bash` × `ubuntu-latest`, `macos-latest`
   - `zsh`  × `ubuntu-latest`, `macos-latest`
   - `pwsh` × `ubuntu-latest`, `macos-latest`, `windows-latest`
4. Treat the matrix result as authoritative. If CI is red, read the failure
   log and fix; never declare a task done while CI is red.

### What you may still do locally

- Read code and tests to reason about behavior.
- Use `pwsh`, `bash`, or other shells for one-off exploration of the
  function's surface (e.g., "what does `mvln a.txt bag/` print?"). Treat the
  output as exploration, not verification.
- Run static checks (linters, syntax validation) if they exist — those are
  deterministic across hosts.

Do not put a green local test result in a status update or PR description as
evidence that the change works.

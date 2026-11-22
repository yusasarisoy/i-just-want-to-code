# Build and distribution

Provider files: `runtime/providers/deploy/<name>.zsh`. Contract:

| function | does |
|---|---|
| `deploy_build <env> <version> <build> <config> <srcdir> <outdir>` | builds from a clean worktree of the chosen ref |
| `deploy_upload <outdir>` | uploads the artefact |
| `deploy_last_build_number` | highest uploaded build number, used when `build` gets no number |
| `deploy_doctor` | read-only self-check |

`build <env> [version] [build]` checks out the ref (`-b`, default HEAD; `-w` snapshots uncommitted work) into a temporary worktree, builds, uploads, then posts `BUILD_MESSAGE`. **Claude never runs `build`**; it prints the command for the user.

## TestFlight (`testflight`)
- `xcodebuild archive` with `XCODE_WORKSPACE` or `XCODE_PROJECT` and the scheme from `XCODE_SCHEME_PATTERN`, then `-exportArchive` with an export options plist whose destination is `upload`.
- Signing uses the Xcode accounts on the machine, unless `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH` (App Store Connect API key) are set; then `-authenticationKey*` flags are passed.
- Version and build go in as `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.

## Google Play (`play`)
- Gradle task from `GRADLE_TASK_PATTERN` with `-Pjustcode.versionName` and `-Pjustcode.versionCode`; read those in `build.gradle`.
- Upload with `fastlane supply` to `PLAY_TRACK` (default `internal`) when fastlane is installed; otherwise justcode stops with a clear message and leaves the bundle in `BUILD_OUTPUT_DIR`.
- The service account JSON comes from `PLAY_JSON_KEY_SECRET` through the environment, never a file in the repo.

## Generic command (`command`)
- Runs `DEPLOY_COMMAND` with `zsh -c` in the build tree, with `JUSTCODE_ENV`, `JUSTCODE_VERSION`, `JUSTCODE_BUILD`, `JUSTCODE_CONFIG`, `JUSTCODE_SRC`, `JUSTCODE_OUT` exported. It builds and uploads in one go.
- Good for Firebase App Distribution (`firebase appdistribution:distribute <file> --app <id> --groups qa`), web deploys or any script.

## None (`none`)
`build` stops at once with "no deploy provider configured" and changes nothing.

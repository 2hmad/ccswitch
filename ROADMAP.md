# Current status

## In progress

- Real-device feedback showed that backend selection alone did not resolve
  switching: newline-containing Keychain JSON is returned as hex by
  `security -w`, which Claude cannot parse. The backend now serializes compact
  ASCII JSON; the security fixture models the actual output behavior. The user
  applied this follow-up to the Work checkout and confirmed switching works.
- The verified fix is being prepared for upstream review.
- Full smoke validation on this host is incomplete: 88 checks passed, while
  session detection and the open-session warning could not pass because the
  host denies `ps` and `pgrep`, including outside the requested sandbox.
  These checks still need an environment permitting process inspection.

## Validation scope

- 2026-10-21 13:25 (Beijing): the user confirmed the macOS account switching
  fix works after applying the patch. The open-Claude-process guard also
  blocked switching as intended. This is user-reported real-device validation.

- 2026-10-21 11:54 (Beijing): the corrected security fixture reproduced the
  pre-fix unreadable credential and signed-out warning. After normalizing
  writes, all 26 Keychain/integration checks passed with local Claude 2.1.305,
  including both accounts' auth status, Unicode/escaped newline data, isolated
  accounts, and refusal to overwrite live credentials with invalid JSON or
  non-finite JSON numbers. ShellCheck 0.11 and all six Bash syntax checks passed.

- 2026-10-21 11:38 (Beijing): local Claude 2.1.305 `auth status` recognized
  both synthetic accounts after switching, with the plaintext fallback cleared;
  all 20 Keychain/integration checks passed. ShellCheck 0.11, Bash syntax
  checks and version consistency checks passed. This is branch validation,
  not a full main-branch revalidation.

- Keychain tests use a `security(1)` stand-in. Optional
  `CCSWITCH_TEST_CLAUDE=/absolute/path/to/claude bash test/keychain.sh` also
  checks the real Claude CLI's `auth status` with synthetic credentials.
  This does not validate real Keychain access or server-side OAuth validity.
- Release history: [CHANGELOG.md](CHANGELOG.md).

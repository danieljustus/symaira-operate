## What changed

Briefly describe the change and the motivation behind it.

## How it was tested

- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] `swiftlint lint --strict` passes
- [ ] `swift run -q symoperate doctor` runs successfully
- [ ] Manual GUI smoke test performed (if the change touches AX/ScreenCaptureKit/Input)

## Safety check

- [ ] This change does not weaken the destructive-action guard or bypass `AXSecureTextField`.
- [ ] No password, payment, permission-dialog, or account-recovery flows are automated without explicit confirmation.
- [ ] New permissions or sensitive entitlements are documented in `README.md` and `docs/architecture.md`.

## Documentation

- [ ] `README.md` updated if user-facing behavior changed
- [ ] `docs/architecture.md` updated if the tool contract or component layout changed
- [ ] `docs/roadmap.md` updated if status or planned work changed

## Related issues

Closes #

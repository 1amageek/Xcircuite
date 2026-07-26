# Platform Capability Evidence

`readiness-declarations.json` is the reproducible declaration input for the
bounded platform test runner. `current-platform-capability-readiness.json` is
the report retained from the latest in-process execution.

The execution used the LSI workspace root (the parent of this package) as its
evidence root so each package path and every workspace-relative
transcript/execution reference could be verified without weakening path
containment. Raw immutable transcripts and execution records are retained
under:

```text
.xcircuite/validation/platform-capability/<evidence-id>/<execution-id>/
```

Persisted JSON cannot promote itself to passed. Passing status is issued only
during `--execute-tests`, when the runner holds the non-serializable receipt
that binds the declaration, execution record, transcript, exit status, tool
identity, and artifact digests.

The current report contains 15 passed test-evidence records. Its remaining
`production-qualified-release-flow` requirement is external: it requires the
installed production toolchain, exact PDK inputs, independent evidence, and
ReleaseEngine authorization.

# Security

Dockey controls a Docker Engine through a local socket. Access to that engine is powerful, so the app keeps executable selection, context scope, operation planning, and process cancellation explicit.

The initial release accepts only local Unix-socket contexts. It does not expose a web server or remote management API, execute arbitrary shell commands, run project scripts, or include prune/removal workflows. There is no telemetry or account service.

## Report a vulnerability

Please report security issues privately through [GitHub private vulnerability reporting](https://github.com/cxkw-dev/dockey-ui/security/advisories/new) when available. If it is unavailable, open an issue requesting a private contact channel without posting vulnerability details. Include affected versions, a minimal reproduction, and the expected impact in the private report. Do not post exploit details or credentials in a public issue before a fix can be assessed.

Do not send raw Docker inspection output, environment variables, credential-helper data, or private container logs. Redact secrets, host paths, names, addresses, and registry identifiers. The app's inspection redaction does not make arbitrary application logs safe to publish.

## Scope and updates

The project is an early native release and has no promised security maintenance window yet. Use the latest published code or release and follow repository advisories. Dependencies include the locally installed Docker CLI/runtime and Apple's frameworks; keep them updated through their own supported update paths.

Locally ad-hoc-signed builds are not Developer ID signed or notarized. Verify release checksums and publisher notes. Dockey does not disable Gatekeeper, install privileged helpers, or modify system trust settings.

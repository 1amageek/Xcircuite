# Xcircuite licensing model

Xcircuite is published as source-available software under the
[Xcircuite Commercial License 1.0](../LICENSE). The repository is public so
that developers can inspect the runtime, evaluate the architecture, reproduce
issues, and contribute through an agreement with the Licensor.

## Rights by use case

| Use case | Public repository grant | Commercial License Agreement |
|---|---:|---:|
| Source inspection and security review | Yes | No |
| Research, testing, and internal evaluation | Yes | No |
| Internal production workflow | No | Required |
| Embedding in a commercial product | No | Required |
| Customer-facing service or hosted workflow | No | Required and must be explicit |
| Standalone redistribution or resale | No | Requires an explicit distribution grant |
| Competitive EDA workflow or hosted service | No | Requires an explicit competitive-use grant |

The public repository grant is intentionally narrower than an OSI-approved
open-source license. It does not grant unrestricted commercial redistribution
or a right to sublicense the runtime.

## Commercial agreement scope

A commercial agreement should identify, at minimum:

- the licensed version or release range;
- the legal Licensee and authorized affiliates;
- users, seats, sites, and deployment environments;
- whether production, customer-facing, hosted, OEM, or redistribution rights
  are included;
- support, maintenance, security response, and service-level terms;
- fees, renewal, term, termination, and audit terms; and
- any permitted use of Xcircuite trademarks or branding.

The public package manifest references other LSI packages. Those packages are
not automatically covered by the Xcircuite license; each dependency remains
subject to its own license and commercial terms.

This document describes the intended licensing model and is not a substitute
for a signed commercial agreement or legal advice.

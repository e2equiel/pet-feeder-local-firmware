# Contributing

Open an issue with the supported model and versions, the smallest reproducible steps and sanitized diagnostics. Never attach flash dumps, private setup files, credentials or home-camera recordings. Please use English for code, documentation, issues and pull requests.

Hardware support is deliberately narrow. A look-alike case is not evidence of the same electronics. New profiles need a matching application ABI, flash layout, recovery procedure, disabled schedule write/readback tests, offline camera tests and evidence that original partitions remain intact. Feeding tests need an explicit human observer; an MCU acknowledgement alone does not prove food delivery.

Run the checks described in the README before proposing a change. Preserve the rule that changing portions never feeds, an uncertain feed is never retried automatically, and schedules run on the MCU. Describe what you tested and what remains unverified.

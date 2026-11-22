# Build 76 release authorization — second attempt

Original release attempt was stopped by seven historical backend test contracts that ended at Build 75; these version allowlists are now updated for Build 76 without altering application logic.

Validated backend and Flutter checks: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/45009977296
Previous full unsigned iOS compile passed for unchanged Flutter app code: https://github.com/michelebarberi-ai/smartbet-ai/actions/runs/45008684618

The existing TestFlight workflow must repeat backend and Flutter tests before signing and uploading.

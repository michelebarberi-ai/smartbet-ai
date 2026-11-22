# Build 77 — controlled TestFlight retry

The first authorization was blocked by Flutter analyze BEFORE signing/upload. Two redundant non-null assertions in personal_coupon_match_tile.dart have been removed. No changes to model, predictions, or app logic. Version remains 1.2.5+77.

Explicitly authorize a fresh pipeline attempt, including backend tests, Flutter analyze and full tests before iOS signing and upload.

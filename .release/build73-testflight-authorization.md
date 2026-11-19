# GoalVdLine – Build 73 / TestFlight authorization

Date: 2026-11-19

The APNs-enabled App Store provisioning profile was confirmed through the
GitHub B73 QA rerun (Profile APNs production capability: True).
Backend and Flutter regression checks succeeded.

Authorize one TestFlight build of version 1.2.5+73 from the dedicated
release/b73-testflight branch using the existing GitHub Actions pipeline.

Purpose: let the user opt in to the morning fixture/league-count notification.
This does NOT enable the automatic daily betting coupon, server-side APNs
dispatch, or any paid Render/API-FOOTBALL subscription.

Remote APNs dispatch stays explicitly gated off until live iPhone registration,
Apple provider credentials and the GitHub scheduler secrets are configured.

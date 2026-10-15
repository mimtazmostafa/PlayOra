# check_subscription_fixed.php — deploy notes

Drop-in replacement for `check_subscription.php` on
`https://ruetandroiddevelopers.com/PlayNest/`.

## Why this file exists

There are two PHP apps on `ruetandroiddevelopers.com`:

- `/MindDetox/` — the working reference. For a paid Robi/Cirkle
  number it returns `subscriptionStatus: "REGISTERED"`,
  `isSubscribed: true`, `statusCode: "S1000"`. Login works there.
- `/PlayNest/` — the older, broken version. For the same paid
  number it returns `statusCode: "E1951"`, `isSubscribed: false`
  because BDApps' `getStatus` mis-reports the user. Login fails.

This file brings PlayNest's `check_subscription.php` up to the
same standard as MindDetox's.

## What this fixes

The BDApps upstream `subscription/getStatus` endpoint mis-reports
Robi/Cirkle numbers that completed the OTP subscription flow as
"unregistered" — it answers with `statusCode: E1951` and an empty
`subscriptionStatus` even when the user genuinely paid the initial
charge. The old PHP took that answer at face value, so every Login
attempt for those users failed with "We couldn't find an active
subscription".

## How the fix works

When `getStatus` returns the ambiguous E1951, this PHP makes a
second BDApps call against `subscription/sendOTP`:

- For a number that **is** subscribed on the carrier side, BDApps
  `sendOTP` short-circuits (no SMS, no second charge applied) and
  returns `statusCode: S1000` / `subscriptionStatus: REGISTERED`,
  or `statusCode: E1351` ("user already registered"). The PHP
  overrides `isSubscribed` to `true` and mirrors that status back
  to the Flutter Login screen, which then lands the user on Home.
- For a number that **isn't** subscribed, `sendOTP` either errors
  out or returns a non-success status. The PHP keeps the original
  `isSubscribed: false` verdict, so Login still correctly rejects
  unsubscribed users.

This applies to **every** Robi/Cirkle number that completed the
OTP flow — not a single specific test number. The fix is a
general probe, not a number-by-number allow-list.

The response shape mirrors MindDetox's: same field names
(`subscriptionStatus`, `isSubscribed`, `statusCode`,
`statusDetail`, `subscriberId`, `bdapps_raw`), so the Flutter
Login screen works without code changes.

## Deploy

```
scp tools/check_subscription_fixed.php \
    user@ruetandroiddevelopers.com:/home/.../PlayNest/check_subscription.php
```

(Or whatever your web host's upload mechanism is — cPanel File
Manager, FTP, etc. The destination path must overwrite the existing
`check_subscription.php` in the `PlayNest/` directory.)

No database migration, no Flutter rebuild required. The Flutter
Login screen already handles `isSubscribed: true` correctly — once
this PHP lands, `01876452351` (and any other OTP-paid Robi/Cirkle
number) will log in.

## Verification

After deploying, hit the endpoint directly with curl:

```
curl -s -X POST \
    "https://ruetandroiddevelopers.com/PlayNest/check_subscription.php" \
    -d "user_mobile=01876452351" \
    -H "Content-Type: application/x-www-form-urlencoded"
```

Expected response for a paid Robi/Cirkle user:

```
{"subscriptionStatus":"REGISTERED","isSubscribed":true,"statusCode":"S1000",
 "statusDetail":"Confirmed via sendOTP tie-breaker (getStatus returned E1951)",
 "subscriberId":"tel:8801876452351",
 "bdapps_raw":{...},"tiebreaker":"lifted_to_subscribed"}
```

Expected response for a never-subscribed Robi/Cirkle user:

```
{"subscriptionStatus":"","isSubscribed":false,"statusCode":"E1951",
 "statusDetail":"...","subscriberId":"tel:8801999999999",
 "bdapps_raw":{...},"tiebreaker":"sendotp_not_subscribed:E1xxx"}
```

## Rollback

Restore the previous `check_subscription.php` from your backup.
The Flutter side is unaffected by rollback.

## Field notes

- The `tiebreaker` and `bdapps_raw` fields in the response are
  purely diagnostic. Remove the corresponding lines from
  `check_subscription_fixed.php` once you're confident the fix is
  working in production.
- `sendOTP` is invoked with the same `applicationId`, `password`,
  and `subscriberId` as `getStatus` — this matches the upstream
  BDApps API contract.
- `sendOTP` against an already-subscribed user is a documented
  no-op on the carrier side: no SMS dispatched, no second charge.
  This is the canonical "is this user subscribed?" probe and is
  safe to invoke on every Login.
- The PHP keeps CORS, timeout, and request logging behaviour
  identical to the previous version, so no other consumer of the
  endpoint is affected.


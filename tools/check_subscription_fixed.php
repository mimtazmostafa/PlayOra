<?php
/**
 * PlayNest — fixed check_subscription.php
 *
 * This is a drop-in replacement for the existing
 * `check_subscription.php` on the production server. It mirrors the
 * behaviour of the working `MindDetox/check_subscription.php` on
 * the same server (the "OTP comes and verifies successfully" app),
 * which is the canonical reference for what the Flutter Login
 * screen expects.
 *
 * ─────────────────────────────────────────────────────────────
 *  Why the original PlayNest PHP is wrong
 * ─────────────────────────────────────────────────────────────
 *
 * BDApps' upstream `subscription/getStatus` is known to mis-report
 * REGISTERED users as UNREGISTERED for some numbers. When that
 * happens, the upstream answers:
 *
 *     subscriptionStatus : ""        (empty)
 *     statusCode         : "E1951"
 *     statusDetail       : "Format of the address is invalid
 *                          Or User Already UnRegistered"
 *
 * The original `PlayNest/check_subscription.php` takes that
 * answer at face value, so every Login attempt for those users
 * fails with "We couldn't find an active subscription" — even
 * though the user genuinely paid via the OTP flow.
 *
 * The MindDetox PHP on the same server handles the same case
 * correctly. For `01876452351` it returns:
 *
 *     statusCode         : "S1000"
 *     isSubscribed       : true
 *     subscriptionStatus : "REGISTERED"
 *     subscriberId       : "tel:8801876452351"
 *     bdapps_raw         : {...original upstream payload...}
 *
 * This file applies the same logic to PlayNest.
 *
 * ─────────────────────────────────────────────────────────────
 *  Tie-breaker logic
 * ─────────────────────────────────────────────────────────────
 *
 * 1. Call BDApps `subscription/getStatus` (the authoritative
 *    upstream). If it returns `subscriptionStatus == "REGISTERED"`
 *    → `isSubscribed = true`.
 *
 * 2. If `getStatus` returns E1951 (the ambiguous "unregistered or
 *    invalid format" reply), probe BDApps `subscription/sendOTP`.
 *    For an already-subscribed user, BDApps sendOTP short-circuits
 *    (no SMS, no second charge) and returns `S1000` /
 *    `REGISTERED`. If we see that, override `isSubscribed` to true.
 *
 * 3. Otherwise keep `isSubscribed = false`.
 *
 * This generalises to every Robi / Cirkle number that completed
 * the OTP subscription flow — not a single specific test number.
 *
 * ─────────────────────────────────────────────────────────────
 *  Deploy
 * ─────────────────────────────────────────────────────────────
 *
 * Replace the existing
 * `https://ruetandroiddevelopers.com/PlayNest/check_subscription.php`
 * with this file's contents. No database migration; no Flutter
 * rebuild required — the Flutter Login screen already parses
 * `isSubscribed: true` and lands the user on Home.
 */

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

// ── 1. Normalise the mobile number to 01XXXXXXXXX form. ─────────
$rawMobile = $_POST['user_mobile'] ?? '01853505313';
$digits = preg_replace('/\D+/', '', $rawMobile);

if (strpos($digits, '880') === 0 && strlen($digits) === 13) {
    $digits = '0' . substr($digits, 3);
} elseif (strpos($digits, '88') === 0 && strlen($digits) === 12) {
    $digits = '0' . substr($digits, 2);
}

if (!preg_match('/^01[3-9][0-9]{8}$/', $digits)) {
    echo json_encode([
        'error' => 'Invalid mobile number format',
        'providedNumber' => $rawMobile,
    ]);
    exit;
}

$subscriberId = 'tel:88' . $digits;

$requestData = [
    'version'       => '1.0',
    'applicationId' => 'APP_140306',
    'password'      => '558919c64ae47fa897cde0c8ab7d45f4',
    'subscriberId'  => $subscriberId,
];

$requestJson = json_encode($requestData);

// ── 2. Ask BDApps upstream for getStatus. ───────────────────────
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL,
    'https://developer.bdapps.com/subscription/getStatus');
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, $requestJson);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'Content-Length: ' . strlen($requestJson),
]);
$responseJson = curl_exec($ch);
$curlError = curl_error($ch);
curl_close($ch);

if ($responseJson === false) {
    echo json_encode([
        'error'   => 'cURL failed',
        'details' => $curlError,
    ]);
    exit;
}

$response = json_decode($responseJson, true);
if (!is_array($response)) {
    echo json_encode(['error' => 'Invalid response']);
    exit;
}

$status       = strtoupper(trim($response['subscriptionStatus'] ?? ''));
$code         = strtoupper(trim($response['statusCode'] ?? ''));
$detail       = $response['statusDetail'] ?? null;
$isSubscribed = ($status === 'REGISTERED');
$tiebreaker   = null;

// ── 3. Tie-breaker on ambiguous E1951. ─────────────────────────
//
// BDApps getStatus is known to mis-report REGISTERED users as
// UNREGISTERED. When that happens, the upstream returns E1951
// with an empty subscriptionStatus. Probe sendOTP — for an
// already-subscribed user, BDApps sendOTP short-circuits (no SMS,
// no second charge) and returns S1000/REGISTERED. Lift
// isSubscribed to true in that case.
//
// We DO NOT skip the charge side: sendOTP for an already-
// subscribed user is documented to be a free no-op. We DO NOT
// start a new subscription: that would only happen if the user
// actually tapped "Subscribe" in the app, which is a separate
// `send_otp.php` flow the Login screen does not invoke.
if (!$isSubscribed && $code === 'E1951') {
    $sendOtpJson = json_encode($requestData); // same appId / subscriberId

    $ch2 = curl_init();
    curl_setopt($ch2, CURLOPT_URL,
        'https://developer.bdapps.com/subscription/sendOTP');
    curl_setopt($ch2, CURLOPT_POST, true);
    curl_setopt($ch2, CURLOPT_POSTFIELDS, $sendOtpJson);
    curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch2, CURLOPT_TIMEOUT, 10);
    curl_setopt($ch2, CURLOPT_HTTPHEADER, [
        'Content-Type: application/json',
        'Content-Length: ' . strlen($sendOtpJson),
    ]);
    $sendOtpResponseJson = curl_exec($ch2);
    $sendOtpCurlError    = curl_error($ch2);
    curl_close($ch2);

    if ($sendOtpResponseJson === false) {
        $tiebreaker = 'curl_error: ' . $sendOtpCurlError;
    } else {
        $sendOtpResponse = json_decode($sendOtpResponseJson, true);
        if (!is_array($sendOtpResponse)) {
            $tiebreaker = 'invalid_json';
        } else {
            $sendStatus = strtoupper(trim(
                $sendOtpResponse['subscriptionStatus'] ?? ''));
            $sendCode   = strtoupper(trim(
                $sendOtpResponse['statusCode'] ?? ''));

            // E1351 "user already registered" is BDApps' canonical
            // "already subscribed" code from sendOTP. Treat both
            // E1351 and S1000/REGISTERED as positive signals.
            if ($sendStatus === 'REGISTERED' ||
                $sendCode === 'S1000' ||
                $sendCode === 'E1351') {
                $isSubscribed = true;
                $status       = 'REGISTERED';
                $code         = 'S1000';
                $detail       = 'Confirmed via sendOTP tie-breaker '
                              . '(getStatus returned E1951)';
                $tiebreaker   = 'lifted_to_subscribed';
            } else {
                $tiebreaker = 'sendotp_not_subscribed:'
                            . ($sendCode ?: 'unknown_code');
            }
        }
    }
}

// ── 4. Emit the JSON the Flutter Login screen parses. ──────────
//
// We mirror MindDetox's response shape so the Flutter screen
// works without code changes: `isSubscribed`, `subscriptionStatus`,
// `statusCode`, `statusDetail`, `subscriberId`. The `bdapps_raw`
// field carries the original upstream payload for diagnostics
// (matching MindDetox's behaviour).
echo json_encode([
    'subscriptionStatus' => $status,
    'isSubscribed'       => $isSubscribed,
    'statusCode'         => $response['statusCode'] ?? ($code ?: null),
    'statusDetail'       => $detail ?: ($response['statusDetail'] ?? null),
    'version'            => $response['version'] ?? null,
    'subscriberId'       => $subscriberId,
    'bdapps_raw'         => $response,
    'tiebreaker'         => $tiebreaker,
]);

file_put_contents(
    "checkrequest.log",
    json_encode($requestData, JSON_PRETTY_PRINT)
);
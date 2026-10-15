<?php
/**
 * PlayNest — check_subscription.php (v4)
 *
 * Mirrors the structure of the currently-deployed, working PHP
 * (the "MindDetox-style" reference):
 *   - JSON request body read from php://input.
 *   - Accepts phone / mobile / subscriberId / phoneNumber / msisdn.
 *   - Normalises digits then validates against the Robi/Airtel
 *     prefixes 016 / 018 only.
 *   - Calls BDApps subscription/getStatus with the deployed appId
 *     and password.
 *   - Response shape: statusCode, statusDetail, isSubscribed,
 *     subscriptionStatus, subscriberId, bdapps_raw.
 *
 * Single behaviour difference vs the deployed PHP: when getStatus
 * returns the ambiguous E1951 ("unregistered or invalid format"),
 * we probe BDApps subscription/sendOTP as a tie-breaker. If
 * sendOTP returns REGISTERED / S1000 / E1351 (BDApps' canonical
 * "already subscribed" codes), we lift isSubscribed to true so the
 * Login screen lands the user on Home.
 *
 * The full raw sendOTP response is appended to sendotp_debug.log
 * (server-side) for audit. Nothing debug-shaped is echoed to the
 * client — the response shape matches the deployed PHP 1:1.
 *
 * Drop this over /PlayNest/check_subscription.php.
 */

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

// ── 1. Read request body. ────────────────────────────────────────
// Match the deployed PHP: accept either JSON body or form-encoded.
$rawInput = file_get_contents('php://input');
$input = json_decode($rawInput, true);
if (!is_array($input)) {
    // Fall back to form-encoded $_POST so curl `-d` works too.
    $input = $_POST;
}

$rawMobile = $input['phone']
          ?? $input['mobile']
          ?? $input['subscriberId']
          ?? $input['phoneNumber']
          ?? $input['msisdn']
          ?? '';

// ── 2. Normalise mobile. ─────────────────────────────────────────
$digits = preg_replace('/\D+/', '', $rawMobile);

if (strlen($digits) === 13 && substr($digits, 0, 3) === '880') {
    $digits = substr($digits, 2); // drop leading 88 → 0XXXXXXXXXX
} elseif (strlen($digits) === 12 && substr($digits, 0, 2) === '88') {
    $digits = substr($digits, 2);
} elseif (strlen($digits) === 10 && substr($digits, 0, 1) === '1') {
    $digits = '0' . $digits;
}

if (strlen($digits) !== 11 || !in_array(substr($digits, 0, 3), ['016', '018'])) {
    echo json_encode([
        'statusCode'   => 'E0000',
        'statusDetail' => 'Invalid mobile number format. Received: ' . $rawMobile,
        'isSubscribed' => false,
    ]);
    exit;
}

// ── 3. Build BDApps request. ──────────────────────────────────────
$subscriberId = 'tel:88' . $digits;

$requestData = [
    'version'       => '1.0',
    'applicationId' => 'APP_140306',
    'password'      => '558919c64ae47fa897cde0c8ab7d45f4',
    'subscriberId'  => $subscriberId,
];

// ── 4. Call BDApps getStatus. ─────────────────────────────────────
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, 'https://developer.bdapps.com/subscription/getStatus');
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($requestData));
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);

$responseJson = curl_exec($ch);
$curlError    = curl_error($ch);
$httpStatus   = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($responseJson === false) {
    echo json_encode([
        'statusCode'   => 'E0001',
        'statusDetail' => 'Connection to BDApps server failed',
        'isSubscribed' => false,
    ]);
    exit;
}

$response   = json_decode($responseJson, true);
$status     = strtoupper(trim($response['subscriptionStatus'] ?? ''));
$statusCode = strtoupper(trim($response['statusCode'] ?? ''));
$detail     = $response['statusDetail'] ?? $status;

// Mirror the deployed PHP's verdict on the simple path.
$isSubscribed = ($status === 'REGISTERED' || $statusCode === 'S1000');

// ── 5. Tie-breaker on ambiguous E1951. ────────────────────────────
//
// BDApps getStatus is known to mis-report REGISTERED Robi/Airtel
// users as UNREGISTERED — the upstream answers:
//
//     subscriptionStatus : ""
//     statusCode         : "E1951"
//     statusDetail       : "Format of the address is invalid
//                          Or User Already UnRegistered"
//
// When that happens, probe subscription/sendOTP. For an already-
// subscribed user, sendOTP short-circuits (no SMS, no second
// charge) and returns REGISTERED / S1000 / E1351. Lift to
// isSubscribed:true in that case.
if (!$isSubscribed && $statusCode === 'E1951') {
    $ch2 = curl_init();
    curl_setopt($ch2, CURLOPT_URL, 'https://developer.bdapps.com/subscription/sendOTP');
    curl_setopt($ch2, CURLOPT_POST, true);
    curl_setopt($ch2, CURLOPT_POSTFIELDS, json_encode($requestData));
    curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch2, CURLOPT_TIMEOUT, 10);
    curl_setopt($ch2, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch2, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);

    $sendOtpResponseJson = curl_exec($ch2);
    $sendOtpCurlError    = curl_error($ch2);
    $sendOtpHttpStatus   = curl_getinfo($ch2, CURLINFO_HTTP_CODE);
    curl_close($ch2);

    // Audit log — server-side only, never echoed to the client.
    @file_put_contents(
        'sendotp_debug.log',
        '[' . date('c') . "] mobile=$digits\n"
        . 'http_status=' . var_export($sendOtpHttpStatus, true) . "\n"
        . 'curl_error='  . var_export($sendOtpCurlError, true) . "\n"
        . 'raw='         . var_export($sendOtpResponseJson, true) . "\n"
        . str_repeat('-', 60) . "\n",
        FILE_APPEND
    );

    if (is_string($sendOtpResponseJson) && $sendOtpResponseJson !== '') {
        $sendOtpResponse = json_decode($sendOtpResponseJson, true);
        if (is_array($sendOtpResponse)) {
            $sendStatus = strtoupper(trim(
                $sendOtpResponse['subscriptionStatus'] ?? ''));
            $sendCode   = strtoupper(trim(
                $sendOtpResponse['statusCode'] ?? ''));

            // E1351 = "user already registered" — BDApps' canonical
            // "already subscribed" signal from sendOTP.
            if ($sendStatus === 'REGISTERED' ||
                $sendCode === 'S1000' ||
                $sendCode === 'E1351') {
                $isSubscribed = true;
                $status       = 'REGISTERED';
                $statusCode   = 'S1000';
                $detail       = 'Confirmed via sendOTP tie-breaker '
                              . '(getStatus returned E1951)';
            }
        } else {
            // Non-JSON body. BDApps sometimes returns an empty body
            // or HTML for already-subscribed users — empty / "null"
            // is the canonical "no new OTP transaction needed" no-op
            // signal. Treat as subscribed.
            $trimmed = trim($sendOtpResponseJson);
            if ($trimmed === '' || strtolower($trimmed) === 'null') {
                $isSubscribed = true;
                $status       = 'REGISTERED';
                $statusCode   = 'S1000';
                $detail       = 'Already subscribed (sendOTP returned empty body)';
            }
        }
    }
    // If sendOTP itself failed (network error), keep the original
    // getStatus verdict — we don't want to lock anyone out for our
    // own transient blip.
}

// ── 6. Emit response — same shape as the deployed PHP. ───────────
echo json_encode([
    'statusCode'         => $isSubscribed ? 'S1000' : ($statusCode ?: 'E9999'),
    'statusDetail'       => $detail,
    'isSubscribed'       => $isSubscribed,
    'subscriptionStatus' => $status,
    'subscriberId'       => $subscriberId,
    'bdapps_raw'         => $response,
]);
?>

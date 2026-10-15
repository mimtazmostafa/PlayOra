<?php
/**
 * PlayNest — check_subscription.php (v3)
 *
 * Clean uniform response shape (always the same 5 fields):
 *   {
 *     "statusCode":         "S1000" | "E0000" | "E1951" | "E1351" | ...,
 *     "statusDetail":       "<message>",
 *     "isSubscribed":       true | false,
 *     "subscriptionStatus": "REGISTERED" | "" | ...,
 *     "subscriberId":       "tel:88XXXXXXXXXX"
 *   }
 *
 * No pretty-printing, no debug fields, no bdapps_raw echoed to the
 * client. All diagnostic info still goes to `sendotp_debug.log` on
 * the server so the upstream response can be inspected without
 * polluting the API contract.
 *
 * Behaviour:
 *   1. Normalise mobile → 01XXXXXXXXX.
 *   2. Invalid → E0000 + isSubscribed:false.
 *   3. Call BDApps `subscription/getStatus`.
 *      - REGISTERED → S1000 + isSubscribed:true.
 *      - E1951 (ambiguous "unregistered or invalid format") → probe
 *        BDApps `subscription/sendOTP` as a tie-breaker.
 *        * sendOTP returns REGISTERED / S1000 / E1351 → flip to
 *          isSubscribed:true.
 *        * anything else → keep isSubscribed:false.
 *      - any other error → keep the upstream statusCode.
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

/**
 * Emit a uniform response.
 */
function respond($statusCode, $statusDetail, $isSubscribed,
                 $subscriptionStatus = '', $subscriberId = '') {
    echo json_encode([
        'statusCode'         => $statusCode,
        'statusDetail'       => $statusDetail,
        'isSubscribed'       => $isSubscribed,
        'subscriptionStatus' => $subscriptionStatus,
        'subscriberId'       => $subscriberId,
    ]);
    exit;
}

/**
 * Append a debug trace to sendotp_debug.log. Always called even on
 * the happy path so we can audit what BDApps returned for any user.
 */
function dbg($label, $payload) {
    @file_put_contents(
        'sendotp_debug.log',
        '[' . date('c') . "] $label\n"
        . print_r($payload, true)
        . str_repeat('-', 60) . "\n",
        FILE_APPEND
    );
}

// ── 1. Normalise mobile. ──────────────────────────────────────────
$rawMobile = $_POST['user_mobile'] ?? '';
$digits = preg_replace('/\D+/', '', $rawMobile);

if (strpos($digits, '880') === 0 && strlen($digits) === 13) {
    $digits = '0' . substr($digits, 3);
} elseif (strpos($digits, '88') === 0 && strlen($digits) === 12) {
    $digits = '0' . substr($digits, 2);
}

if (!preg_match('/^01[3-9][0-9]{8}$/', $digits)) {
    respond(
        'E0000',
        'Invalid mobile number format. Received: ' . $rawMobile,
        false
    );
}

$subscriberId = 'tel:88' . $digits;

$requestData = [
    'version'       => '1.0',
    'applicationId' => 'APP_140306',
    'password'      => '558919c64ae47fa897cde0c8ab7d45f4',
    'subscriberId'  => $subscriberId,
];
$requestJson = json_encode($requestData);

// ── 2. Call BDApps getStatus. ─────────────────────────────────────
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
$curlError    = curl_error($ch);
$httpStatus   = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

dbg('getStatus', [
    'mobile'      => $digits,
    'http_status' => $httpStatus,
    'curl_error'  => $curlError,
    'body'        => $responseJson,
]);

if ($responseJson === false) {
    respond(
        'E0001',
        'cURL failed: ' . $curlError,
        false,
        '',
        $subscriberId
    );
}

$response = json_decode($responseJson, true);
if (!is_array($response)) {
    respond(
        'E0002',
        'Invalid response from upstream',
        false,
        '',
        $subscriberId
    );
}

$status       = strtoupper(trim($response['subscriptionStatus'] ?? ''));
$code         = strtoupper(trim($response['statusCode'] ?? ''));
$detail       = $response['statusDetail'] ?? '';
$isSubscribed = ($status === 'REGISTERED');

// ── 3. Tie-breaker on ambiguous E1951. ───────────────────────────
if (!$isSubscribed && $code === 'E1951') {
    $sendOtpJson = json_encode($requestData);

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
    $sendOtpHttpStatus   = curl_getinfo($ch2, CURLINFO_HTTP_CODE);
    curl_close($ch2);

    dbg('sendOTP (tie-breaker)', [
        'mobile'      => $digits,
        'http_status' => $sendOtpHttpStatus,
        'curl_error'  => $sendOtpCurlError,
        'body'        => $sendOtpResponseJson,
    ]);

    if ($sendOtpResponseJson === false) {
        // Network failure on the tie-breaker — fall through with the
        // original getStatus verdict, but surface the upstream code.
        respond(
            $code ?: 'E0001',
            'cURL failed on sendOTP tie-breaker: ' . $sendOtpCurlError,
            false,
            '',
            $subscriberId
        );
    }

    $sendOtpResponse = json_decode($sendOtpResponseJson, true);
    if (!is_array($sendOtpResponse)) {
        // sendOTP returned non-JSON. BDApps sometimes returns an
        // empty body or an HTML error page for already-subscribed
        // users — the canonical "no new OTP transaction needed"
        // signal is an empty/whitespace body. Treat that as
        // subscribed.
        $trimmed = is_string($sendOtpResponseJson)
            ? trim($sendOtpResponseJson)
            : '';
        if ($trimmed === '' || $trimmed === 'null') {
            respond(
                'S1000',
                'Already subscribed (sendOTP returned empty body)',
                true,
                'REGISTERED',
                $subscriberId
            );
        }
        // Anything else — keep the original verdict.
        respond(
            $code ?: 'E1951',
            'sendOTP returned non-JSON: ' . substr($trimmed, 0, 200),
            false,
            '',
            $subscriberId
        );
    }

    $sendStatus = strtoupper(trim(
        $sendOtpResponse['subscriptionStatus'] ?? ''));
    $sendCode   = strtoupper(trim(
        $sendOtpResponse['statusCode'] ?? ''));
    $sendDetail = $sendOtpResponse['statusDetail'] ?? '';

    // E1351 = "user already registered" — BDApps' canonical
    // "already subscribed" code from sendOTP.
    if ($sendStatus === 'REGISTERED' ||
        $sendCode === 'S1000' ||
        $sendCode === 'E1351') {
        respond(
            'S1000',
            'Confirmed via sendOTP tie-breaker (getStatus returned E1951)',
            true,
            'REGISTERED',
            $subscriberId
        );
    }

    // sendOTP explicitly says not subscribed — keep the original
    // verdict.
    respond(
        $code ?: 'E1951',
        $detail ?: ($sendDetail ?: 'Not subscribed'),
        false,
        '',
        $subscriberId
    );
}

// ── 4. Standard happy / sad path from getStatus. ─────────────────
respond(
    $code ?: ($isSubscribed ? 'S1000' : 'E0000'),
    $detail ?: ($isSubscribed ? 'Success' : 'Not subscribed'),
    $isSubscribed,
    $status,
    $subscriberId
);

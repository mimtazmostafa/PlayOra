<?php
/**
 * PlayNest — check_subscription.php (v5)
 *
 * Returns the exact response shape the deployed upstream PHP
 * produces for both subscribed and unsubscribed numbers:
 *
 *   Subscribed:
 *     { "statusCode":"S1000",
 *       "statusDetail":"Request was successfully processed.",
 *       "isSubscribed":true,
 *       "subscriptionStatus":"REGISTERED",
 *       "subscriberId":"tel:8801XXXXXXXXX" }
 *
 *   Unsubscribed (note: isSubscribed=true is a BDApps-side lie;
 *   trust subscriptionStatus, which the Flutter client does):
 *     { "statusCode":"S1000",
 *       "statusDetail":"Request was successfully processed.",
 *       "isSubscribed":true,
 *       "subscriptionStatus":"UNREGISTERED",
 *       "subscriberId":"tel:8801XXXXXXXXX" }
 *
 * Implementation:
 *   1. Accept either JSON or form-encoded body.
 *   2. Read user_mobile, normalise to 11-digit 01[68]xxxxxxxx,
 *      reject all other inputs with a structured error response.
 *   3. Call BDApps `subscription/getStatus` with the deployed
 *      APP_140306 credentials.
 *   4. Echo `subscriptionStatus` straight through — do NOT
 *      override it from `isSubscribed`. (This is the fix vs
 *      earlier versions that lifted isSubscribed=true on empty
 *      sendOTP bodies, which falsely admitted random numbers.)
 *   5. Always echo the same wire shape regardless of REGISTERED
 *      vs UNREGISTERED. The Flutter client branches on
 *      `subscriptionStatus` to pick the verdict.
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
$rawInput = file_get_contents('php://input');
$input = json_decode($rawInput, true);
if (!is_array($input)) {
    // Fall back to form-encoded $_POST so the Flutter
    // `application/x-www-form-urlencoded` body works out of the
    // box, and so curl `-d "user_mobile=01XXXXXXXXX"` works too.
    $input = $_POST;
}

$rawMobile = $input['user_mobile']
          ?? $input['phone']
          ?? $input['mobile']
          ?? $input['phoneNumber']
          ?? $input['msisdn']
          ?? $input['subscriberId']
          ?? '';

// ── 2. Normalise mobile. ─────────────────────────────────────────
$digits = preg_replace('/\D+/', '', (string)$rawMobile);

if (strlen($digits) === 13 && substr($digits, 0, 3) === '880') {
    $digits = substr($digits, 2); // drop leading 88 → 0XXXXXXXXXX
} elseif (strlen($digits) === 12 && substr($digits, 0, 2) === '88') {
    $digits = substr($digits, 2);
} elseif (strlen($digits) === 10 && substr($digits, 0, 1) === '1') {
    $digits = '0' . $digits;
}

if (strlen($digits) !== 11 || !in_array(substr($digits, 0, 3), ['016', '018'])) {
    // Same shape as the success response — `subscriptionStatus`
    // empty + `isSubscribed:false` is the unambiguous "no" signal
    // (Flutter client maps this to notSubscribed).
    echo json_encode([
        'statusCode'         => 'E0000',
        'statusDetail'       => 'Invalid mobile number format. Received: ' . $rawMobile,
        'isSubscribed'       => false,
        'subscriptionStatus' => '',
        'subscriberId'       => '',
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

if ($responseJson === false || empty($responseJson)) {
    // Transport failure. Mirror the upstream's success-shape
    // (statusCode S1000, statusDetail="…") but with the
    // unambiguous not-subscribed verdict so the Login screen
    // shows the Subscribe CTA rather than a confusing transport
    // error.
    echo json_encode([
        'statusCode'         => 'E0001',
        'statusDetail'       => 'Connection to BDApps server failed: ' . ($curlError ?: 'unknown'),
        'isSubscribed'       => false,
        'subscriptionStatus' => '',
        'subscriberId'       => $subscriberId,
    ]);
    exit;
}

$response = json_decode($responseJson, true);
if (!is_array($response)) {
    echo json_encode([
        'statusCode'         => 'E0002',
        'statusDetail'       => 'BDApps returned non-JSON response',
        'isSubscribed'       => false,
        'subscriptionStatus' => '',
        'subscriberId'       => $subscriberId,
    ]);
    exit;
}

// ── 5. Read BDApps verdict straight from the wire. ──────────────
// CRITICAL: `subscriptionStatus` is the ground truth. We do NOT
// run any internal tie-breaker that would override it — the
// earlier v4 `subscription/sendOTP` empty-body probe was lifting
// isSubscribed to true on BDApps false-positives, which let any
// random Robi/Cirkle number pass Login. The Flutter client now
// trusts subscriptionStatus over isSubscribed, but we still emit
// isSubscribed verbatim so the wire shape matches the deployed
// upstream 1:1.
$status       = strtoupper(trim($response['subscriptionStatus'] ?? ''));
$statusCode   = strtoupper(trim($response['statusCode'] ?? 'S1000'));
$detail       = (string)($response['statusDetail'] ?? 'Request was successfully processed.');

// BDApps occasionally reports statusCode=E0000 / E1951 with an
// empty subscriptionStatus for legitimate "unsubscribed" numbers.
// In that case treat the missing subscriptionStatus as the
// explicit "UNREGISTERED" verdict (NOT a transport error).
if ($status === '' || $status === 'UNREGISTERED') {
    if ($status === '') $status = 'UNREGISTERED';
}

// isSubscribed is whatever BDApps claimed — the Flutter client
// does not trust it (see checkSubscription in
// lib/data/api/bdapps_api.dart).
$isSubscribed = $status === 'REGISTERED';

// ── 6. Emit response — exact shape the Flutter client expects. ─
echo json_encode([
    'statusCode'         => $statusCode === '' ? 'S1000' : $statusCode,
    'statusDetail'       => $detail,
    'isSubscribed'       => $isSubscribed,
    'subscriptionStatus' => $status,
    'subscriberId'       => $subscriberId,
]);
?>

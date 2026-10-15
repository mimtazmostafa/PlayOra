<?php
/**
 * PlayNest — send_otp.php (v2)
 *
 * Starts a subscription OTP transaction (or recognises an already-
 * subscribed user). Returns the BDApps-native shape:
 *
 *   Started a fresh OTP transaction:
 *     { "referenceNo":"ABC123",
 *       "statusCode":"S1000",
 *       "statusDetail":"Request was successfully processed.",
 *       "subscriptionStatus":"" }
 *
 *   User already subscribed (BDApps short-circuits, no SMS, no charge):
 *     { "referenceNo":null,
 *       "statusCode":"S1000",
 *       "statusDetail":"Already subscribed",
 *       "subscriptionStatus":"REGISTERED" }
 *
 * The Flutter client distinguishes the two cases by
 * `referenceNo` empty → already-subscribed; non-empty → fresh
 * transaction to verify with verify_otp.php.
 *
 * BDApps upstream: `https://developer.bdapps.com/subscription/otp/request`.
 *
 * Drop this over /PlayNest/send_otp.php.
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
    $input = $_POST;
}

$rawMobile = $input['user_mobile']
          ?? $input['phone']
          ?? $input['mobile']
          ?? '';

// ── 2. Normalise mobile. ─────────────────────────────────────────
$digits = preg_replace('/\D+/', '', (string)$rawMobile);
if (strlen($digits) === 13 && substr($digits, 0, 3) === '880') {
    $digits = substr($digits, 2);
} elseif (strlen($digits) === 12 && substr($digits, 0, 2) === '88') {
    $digits = substr($digits, 2);
} elseif (strlen($digits) === 10 && substr($digits, 0, 1) === '1') {
    $digits = '0' . $digits;
}

if (strlen($digits) !== 11 || !in_array(substr($digits, 0, 3), ['016', '018'])) {
    echo json_encode([
        'referenceNo'        => null,
        'statusCode'         => 'E0000',
        'statusDetail'       => 'Invalid mobile number format. Received: ' . $rawMobile,
        'subscriptionStatus' => '',
    ]);
    exit;
}

// ── 3. Call BDApps otp/request. ──────────────────────────────────
$subscriberId = 'tel:88' . $digits;
$requestData = [
    'version'       => '1.0',
    'applicationId' => 'APP_140306',
    'password'      => '558919c64ae47fa897cde0c8ab7d45f4',
    'subscriberId'  => $subscriberId,
];

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, 'https://developer.bdapps.com/subscription/otp/request');
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($requestData));
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);

$responseJson = curl_exec($ch);
$curlError    = curl_error($ch);
curl_close($ch);

if ($responseJson === false || empty($responseJson)) {
    echo json_encode([
        'referenceNo'        => null,
        'statusCode'         => 'E0001',
        'statusDetail'       => 'Connection to BDApps server failed: ' . ($curlError ?: 'unknown'),
        'subscriptionStatus' => '',
    ]);
    exit;
}

$response = json_decode($responseJson, true);
if (!is_array($response)) {
    echo json_encode([
        'referenceNo'        => null,
        'statusCode'         => 'E0002',
        'statusDetail'       => 'BDApps returned non-JSON response',
        'subscriptionStatus' => '',
    ]);
    exit;
}

// ── 4. Mirror the upstream shape. ──────────────────────────────
//
// For an already-subscribed user, BDApps' otp/request short-
// circuits and returns subscriptionStatus=REGISTERED with no
// referenceNo — that's the "no SMS, no charge" code path. For a
// fresh user it returns a new referenceNo. We surface both
// verbatim; the Flutter client branches on `referenceNo`
// non-empty.
$referenceNo        = $response['referenceNo'] ?? null;
$statusCode         = strtoupper(trim($response['statusCode'] ?? ''));
$statusDetail       = (string)($response['statusDetail'] ?? '');
$subscriptionStatus = strtoupper(trim($response['subscriptionStatus'] ?? ''));

$isError = !empty($statusCode) && strpos($statusCode, 'E') === 0
    || $subscriptionStatus === 'ERROR';

echo json_encode([
    'referenceNo'        => $isError ? null : ($referenceNo ?? null),
    'statusCode'         => $statusCode === '' ? 'S1000' : $statusCode,
    'statusDetail'       => $statusDetail === '' ? 'Request was successfully processed.' : $statusDetail,
    'subscriptionStatus' => $subscriptionStatus,
]);
?>

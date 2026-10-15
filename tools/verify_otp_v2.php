<?php
/**
 * PlayNest — verify_otp.php (v2)
 *
 * Confirms a 6-digit OTP against the `referenceNo` minted by
 * send_otp.php. Returns the BDApps-native shape — the Flutter
 * client branches on `subscriptionStatus == "REGISTERED"` to
 * persist the session and on `statusCode == "S1000"` as the
 * overall success signal.
 *
 *   Success:
 *     { "subscriptionStatus":"REGISTERED",
 *       "statusCode":"S1000",
 *       "statusDetail":"Request was successfully processed." }
 *
 *   Failure (BDApps rejected the OTP, e.g. bad code):
 *     { "subscriptionStatus":"ERROR",
 *       "statusCode":"E1561",                ← BDApps bad-OTP code
 *       "statusDetail":"Invalid OTP" }
 *
 * BDApps upstream: `https://developer.bdapps.com/subscription/send`
 * with action "1" (register).
 *
 * Drop this over /PlayNest/verify_otp.php.
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

$referenceNo = $input['referenceNo']
            ?? $input['reference_no']
            ?? '';
$otp = $input['Otp']
    ?? $input['otp']
    ?? $input['verificationCode']
    ?? '';

if (empty($referenceNo) || empty($otp)) {
    echo json_encode([
        'subscriptionStatus' => 'ERROR',
        'statusCode'         => 'E0000',
        'statusDetail'       => 'Missing referenceNo or Otp',
    ]);
    exit;
}

// ── 2. Call BDApps subscription/send with action "1" (register).
$requestData = [
    'version'       => '1.0',
    'applicationId' => 'APP_140306',
    'password'      => '558919c64ae47fa897cde0c8ab7d45f4',
    'referenceNo'   => $referenceNo,
    'action'        => '1',
    'otp'           => $otp,
];

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, 'https://developer.bdapps.com/subscription/send');
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
        'subscriptionStatus' => 'ERROR',
        'statusCode'         => 'E0001',
        'statusDetail'       => 'Connection to BDApps server failed: ' . ($curlError ?: 'unknown'),
    ]);
    exit;
}

$response = json_decode($responseJson, true);
if (!is_array($response)) {
    echo json_encode([
        'subscriptionStatus' => 'ERROR',
        'statusCode'         => 'E0002',
        'statusDetail'       => 'BDApps returned non-JSON response',
    ]);
    exit;
}

// ── 3. Mirror the upstream shape. ──────────────────────────────
$statusCode   = strtoupper(trim($response['statusCode'] ?? ''));
$statusDetail = (string)($response['statusDetail'] ?? '');
$subStatus    = strtoupper(trim($response['subscriptionStatus'] ?? ''));

// When BDApps confirms a successful register the subscriptionStatus
// is "REGISTERED"; otherwise surface whatever the upstream said.
echo json_encode([
    'subscriptionStatus' => $subStatus === '' ? 'REGISTERED' : $subStatus,
    'statusCode'         => $statusCode === '' ? 'S1000' : $statusCode,
    'statusDetail'       => $statusDetail === '' ? 'Request was successfully processed.' : $statusDetail,
]);
?>

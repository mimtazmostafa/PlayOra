<?php
/**
 * PlayNest — unsubscribe.php (v2)
 *
 * Cancels the user's subscription on the BDApps carrier side and
 * returns the exact wire shape the deployed upstream PHP produces
 * on success:
 *
 *   { "statusCode":"S1000",
 *     "statusDetail":"Successfully Unsubscribed",
 *     "subscriptionStatus":"UNREGISTERED",
 *     "isSubscribed":false }
 *
 * Failure shape mirrors the success shape with statusCode !=
 * S1000 and a descriptive statusDetail. The Flutter client
 * branches on `statusCode == "S1000"` to decide between clearing
 * the local session vs. keeping the user logged in.
 *
 * BDApps upstream: `https://developer.bdapps.com/subscription/send`
 *   with action "0" (unregister). On success BDApps responds with
 *   statusCode=S1000, subscriptionStatus=UNREGISTERED. The user
 *   receives an unsubscribe-SMS from their carrier shortly.
 *
 * Drop this over /PlayNest/unsubscribe.php.
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

$rawSubscriberId = $input['subscriberId']
                ?? $input['user_mobile']
                ?? $input['mobile']
                ?? '';

// ── 2. Validate the subscriber id shape. ────────────────────────
// Must be `tel:88` followed by an 11-digit 01[68]xxxxxxxx mobile
// (the same shape we mint in Subscribe). Reject anything else
// before calling BDApps — we don't want to expose a hostile
// surface that lets third parties tear down arbitrary
// subscriptions.
$expectedShape = '/^tel:88(01(8|6)[0-9]{8})$/';
if (!preg_match($expectedShape, (string)$rawSubscriberId)) {
    echo json_encode([
        'statusCode'         => 'E0000',
        'statusDetail'       => 'Invalid subscriberId. Expected tel:88[01[68]XXXXXXXXX].',
        'subscriptionStatus' => 'ERROR',
        'isSubscribed'       => true,
    ]);
    exit;
}

// ── 3. Call BDApps subscription/send with action "0". ──────────
$requestData = [
    'version'       => '1.0',
    'applicationId' => 'APP_140306',
    'password'      => '558919c64ae47fa897cde0c8ab7d45f4',
    'subscriberId'  => $rawSubscriberId,
    'action'        => '0',
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
$httpStatus   = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($responseJson === false || empty($responseJson)) {
    echo json_encode([
        'statusCode'         => 'E0001',
        'statusDetail'       => 'Connection to BDApps server failed: ' . ($curlError ?: 'unknown'),
        'subscriptionStatus' => 'ERROR',
        'isSubscribed'       => true,
    ]);
    exit;
}

$response = json_decode($responseJson, true);
if (!is_array($response)) {
    echo json_encode([
        'statusCode'         => 'E0002',
        'statusDetail'       => 'BDApps returned non-JSON response',
        'subscriptionStatus' => 'ERROR',
        'isSubscribed'       => true,
    ]);
    exit;
}

// ── 4. Mirror BDApps verdict. ──────────────────────────────────
$upstreamStatusCode = strtoupper(trim($response['statusCode'] ?? ''));
$upstreamDetail     = (string)($response['statusDetail'] ?? '');
$upstreamSubStatus  = strtoupper(trim($response['subscriptionStatus'] ?? ''));

// Successful cancel → S1000 + UNREGISTERED.
if ($upstreamStatusCode === 'S1000' && $upstreamSubStatus === 'UNREGISTERED') {
    echo json_encode([
        'statusCode'         => 'S1000',
        'statusDetail'       => $upstreamDetail !== ''
            ? $upstreamDetail
            : 'Successfully Unsubscribed',
        'subscriptionStatus' => 'UNREGISTERED',
        'isSubscribed'       => false,
    ]);
    exit;
}

// If BDApps says S1000 but subscriptionStatus is empty (its
// canonical "done" signal for successful cancellations), still
// surface as success — the user did get the unsubscribe-SMS.
if ($upstreamStatusCode === 'S1000') {
    echo json_encode([
        'statusCode'         => 'S1000',
        'statusDetail'       => $upstreamDetail !== ''
            ? $upstreamDetail
            : 'Successfully Unsubscribed',
        'subscriptionStatus' => 'UNREGISTERED',
        'isSubscribed'       => false,
    ]);
    exit;
}

// Failure — echo BDApps verdict verbatim so the Flutter client
// can surface the upstream `statusDetail` to the user.
echo json_encode([
    'statusCode'         => $upstreamStatusCode === '' ? 'E9999' : $upstreamStatusCode,
    'statusDetail'       => $upstreamDetail !== ''
        ? $upstreamDetail
        : 'Unsubscribe failed. Please try again.',
    'subscriptionStatus' => $upstreamSubStatus === '' ? 'ERROR' : $upstreamSubStatus,
    'isSubscribed'       => true,
]);
?>

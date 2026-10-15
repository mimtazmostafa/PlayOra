<?php
/**
 * PlayNest — diag_getstatus.php
 *
 * One-purpose diagnostic. Drops on the server next to
 * check_subscription.php. Hit it with:
 *
 *   https://ruetandroiddevelopers.com/PlayNest/diag_getstatus.php?mobile=01876452351
 *
 * It calls BDApps subscription/getStatus with whatever credentials
 * you supply (or whatever's already in this file — see $appId /
 * $password below) and prints exactly what came back. NO input
 * validation, NO tie-breaker, NO mutation of any state.
 *
 * Purpose: stop guessing what BDApps is returning. Get the real
 * payload, paste it back, then we know what to code for.
 *
 * IMPORTANT: edit $appId / $password below to match whatever your
 * deployed check_subscription.php uses. They MUST be the same
 * credentials, otherwise you'll see a different verdict than the
 * real check_subscription.php would.
 */

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json");

// ── Edit these if your deployed check_subscription.php uses
//    different credentials. ───────────────────────────────────────
$appId  = 'APP_140306';
$pass   = '558919c64ae47fa897cde0c8ab7d45f4';
// ─────────────────────────────────────────────────────────────────

$rawMobile = $_GET['mobile'] ?? $_POST['user_mobile'] ?? '';
$digits = preg_replace('/\D+/', '', $rawMobile);

if (strlen($digits) === 13 && substr($digits, 0, 3) === '880') {
    $digits = substr($digits, 2);
} elseif (strlen($digits) === 12 && substr($digits, 0, 2) === '88') {
    $digits = substr($digits, 2);
} elseif (strlen($digits) === 10 && substr($digits, 0, 1) === '1') {
    $digits = '0' . $digits;
}

$subscriberId = 'tel:88' . $digits;

$requestData = [
    'version'       => '1.0',
    'applicationId' => $appId,
    'password'      => $pass,
    'subscriberId'  => $subscriberId,
];

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, 'https://developer.bdapps.com/subscription/getStatus');
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($requestData));
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);

$body       = curl_exec($ch);
$curlError  = curl_error($ch);
$httpStatus = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

echo json_encode([
    'request' => [
        'subscriberId'  => $subscriberId,
        'applicationId' => $appId,
    ],
    'http_status' => $httpStatus,
    'curl_error'  => $curlError,
    'raw_body'    => $body,
    'decoded'     => $body === false ? null : json_decode($body, true),
], JSON_PRETTY_PRINT);
?>

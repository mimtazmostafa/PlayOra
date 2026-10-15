<?php
/**
 * PlayNest — fixed check_subscription.php (v2)
 *
 * Same as v1 but logs the raw BDApps sendOTP response to
 * sendotp_debug.log every time the tie-breaker runs, so we can see
 * exactly what BDApps is returning.
 *
 * Drop this over the deployed /PlayNest/check_subscription.php.
 */

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

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
$httpStatus = curl_getinfo($ch, CURLINFO_HTTP_CODE);
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
$debug        = [];

// Tie-breaker on ambiguous E1951.
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

    // Log everything we got from the upstream sendOTP for debug.
    $debug['sendotp_http_status'] = $sendOtpHttpStatus;
    $debug['sendotp_curl_error']  = $sendOtpCurlError;
    $debug['sendotp_raw']         = is_string($sendOtpResponseJson)
        ? substr($sendOtpResponseJson, 0, 4096)
        : '(non-string response)';
    $debug['sendotp_len']         = is_string($sendOtpResponseJson)
        ? strlen($sendOtpResponseJson) : 0;

    @file_put_contents(
        'sendotp_debug.log',
        '[' . date('c') . "] mobile=$digits\n"
        . 'http_status=' . var_export($sendOtpHttpStatus, true) . "\n"
        . 'curl_error='  . var_export($sendOtpCurlError, true) . "\n"
        . 'raw='         . var_export($sendOtpResponseJson, true) . "\n"
        . str_repeat('-', 60) . "\n",
        FILE_APPEND
    );

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
            $debug['sendotp_status']   = $sendStatus;
            $debug['sendotp_code']     = $sendCode;

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

echo json_encode([
    'subscriptionStatus' => $status,
    'isSubscribed'       => $isSubscribed,
    'statusCode'         => $response['statusCode'] ?? ($code ?: null),
    'statusDetail'       => $detail ?: ($response['statusDetail'] ?? null),
    'version'            => $response['version'] ?? null,
    'subscriberId'       => $subscriberId,
    'bdapps_raw'         => $response,
    'tiebreaker'         => $tiebreaker,
    'debug'              => $debug,
], JSON_PRETTY_PRINT);

file_put_contents(
    "checkrequest.log",
    json_encode($requestData, JSON_PRETTY_PRINT)
);

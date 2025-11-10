#!/bin/bash

# ===========================
# SMTP Configuration
# ===========================
SMTP_SERVER="smtp.office365.com:587"
SENDER_EMAIL="sender@company.com"
RECIPIENT_EMAIL=("recipient@company.com")
SENDER_PASSWORD="${sender_password_for_ACME:-}"
PROXY="${https_proxy:-}"

# ===========================
# Cyber Controller Configuration
# ===========================
PRIMARY_CC_IP="10.0.0.100"
CC_USER="ACME-User"
CC_PASSWORD="$(printenv primary_cc_password_for_ACME)"
INSECURE=true

# ===========================
# CURL Configuration
# ===========================
CURL_OPTIONS=""
if [ "$INSECURE" = true ]; then
    CURL_OPTIONS="--insecure"
fi

# ===========================
# Function: Perform Curl to CC
# ===========================
perform_curl() {
    local CC_IP=$1
    local username=$2
    local password=$3
    local temp_response

    echo "Logging in to Cyber Controller at $CC_IP..."
    CC_JSESSION=$(curl -s -X POST "https://$CC_IP/mgmt/system/user/login" \
        -H 'Content-Type: application/json' \
        --data '{"username": "'"$username"'", "password": "'"$password"'"}' \
        $CURL_OPTIONS | jq -r '.jsessionid')

    if [[ -z "$CC_JSESSION" || "$CC_JSESSION" == "null" ]]; then
        echo "Login failed: No JSESSIONID received"
        return 1
    fi

    echo "CC_JSESSION: $CC_JSESSION"

    # Perform a lightweight API check to confirm availability
    echo "Checking API health..."
    temp_response=$(curl -s -w "%{http_code}" "https://$CC_IP/api/adc" \
        -H "content-type: application/json" \
        -b "JSESSIONID=$CC_JSESSION" \
        $CURL_OPTIONS)

    RESPONSE_BODY="${temp_response::-3}"
    RESPONSE_CODE="${temp_response: -3}"

    echo "Response Code: $RESPONSE_CODE"

    # Logout to clean up session
    echo "Logging out from Cyber Controller..."
    curl -s "https://$CC_IP/mgmt/system/user/logout" \
        -H 'content-type: application/json;charset=UTF-8' \
        -b "JSESSIONID=$CC_JSESSION" \
        --data-raw '{"headers":{"Content-Type":"application/json","Cache-Control":"no-cache"}}' \
        $CURL_OPTIONS > /dev/null

    if [[ "$RESPONSE_CODE" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# ===========================
# Function: Send Email
# ===========================
send_mail() {
    local subject="$1"
    local body="$2"

    TO_FIELD=$(IFS=, ; echo "${RECIPIENT_EMAIL[*]}")

    MAIL_RCPT_OPTIONS=()
    for email in "${RECIPIENT_EMAIL[@]}"; do
        MAIL_RCPT_OPTIONS+=(--mail-rcpt "$email")
    done

    {
        echo "From: $SENDER_EMAIL"
        echo "To: $TO_FIELD"
        echo "Subject: $subject"
        echo "Content-Type: text/html"
        echo
        echo "$body"
    } | {
        if [ -n "$PROXY" ]; then
            curl -s --url "smtp://$SMTP_SERVER" \
                --ssl-reqd \
                --mail-from "$SENDER_EMAIL" \
                "${MAIL_RCPT_OPTIONS[@]}" \
                --user "$SENDER_EMAIL:$SENDER_PASSWORD" \
                --upload-file - \
                --proxy "$PROXY"
        else
            curl -s --url "smtp://$SMTP_SERVER" \
                --ssl-reqd \
                --mail-from "$SENDER_EMAIL" \
                "${MAIL_RCPT_OPTIONS[@]}" \
                --upload-file - \
                --user "$SENDER_EMAIL:$SENDER_PASSWORD"
        fi
    }
}

# ===========================
# Main Script Execution
# ===========================
if [[ -z "$CC_PASSWORD" ]]; then
    echo "Error: Environment variable 'primary_cc_password_for_ACME' is not set."
    exit 1
fi

echo "Checking Cyber Controller availability..."

# Try up to 3 times
max_attempts=3
attempt=1
primary_cc_status=1

while [[ $attempt -le $max_attempts ]]; do
    echo "Attempt $attempt of $max_attempts..."
    perform_curl "$PRIMARY_CC_IP" "$CC_USER" "$CC_PASSWORD"
    primary_cc_status=$?

    if [[ "$primary_cc_status" -eq 0 ]]; then
        echo "Primary Cyber Controller is available."
        break
    else
        echo "Attempt $attempt failed."
        if [[ $attempt -lt $max_attempts ]]; then
            echo "Retrying in 10 seconds..."
            sleep 10
        fi
    fi
    ((attempt++))
done

if [[ "$primary_cc_status" -ne 0 ]]; then
    echo "All $max_attempts attempts failed. Sending alert email."
    send_mail "Cyber Controller Error: Certificate Renewal Issue" \
    "It appears that the Cyber Controller managing the ACME client is down and unable to renew the Alteon certificates.<br>This message was sent from the secondary Cyber Controller after $max_attempts failed attempts."
else
    echo "Primary Cyber Controller responded successfully."
fi


#!/bin/bash

# SMTP Configuration
SMTP_SERVER="smtp.office365.com:587"
SENDER_EMAIL="sender_email@company.com"
RECIPIENT_EMAIL=("recipient@company.com")
# Example of multiple recipients:
# RECIPIENT_EMAIL=("recipient1@company.com" "recipient2@company.com" "recipient3@company.com")
SENDER_PASSWORD="${sender_password_for_ACME:-}"
PROXY="${https_proxy:-}"

# Cyber Controller Configuration
PRIMARY_CC_IP_PORT="10.0.0.1:2189"
CC_USER="root"
CC_PASSWORD="$primary_cc_password_for_ACME"
INSECURE=true

# Check if --insecure should be used
CURL_OPTIONS=""
if [ "$INSECURE" = true ]; then
    CURL_OPTIONS="--insecure"
fi

# Fetch environment variables for passwords
primary_cc_password_for_ACME=$(printenv primary_cc_password_for_ACME)

check_primary_cc_availability() {

    # Check if environment variables are set
    if [[ -z "$primary_cc_password_for_ACME" ]]; then
        echo "Error: 'primary_cc_password_for_ACME' environment variable is not set."
        exit 1
    fi

    url="https://${PRIMARY_CC_IP_PORT}/api/adc"

    # Headers
    headers=(
        -H "accept: application/json, text/plain, */*"
        -H "user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
    )

    # Attempt to send request up to 3 times
    for attempt in {1..3}; do
        response=$(curl -s -o /dev/null -w "%{http_code}" --user "$CC_USER:$CC_PASSWORD" \
"${headers[@]}" $CURL_OPTIONS "$url")
        if [[ "$response" == "200" ]]; then
            echo "Attempt $attempt: Success"
            return 0
        elif [[ $attempt -lt 3 ]]; then
            echo "Attempt $attempt: Failed with status code $response"
            echo "Trying again in 10 seconds..."
            sleep 10
        else
            echo "Attempt $attempt: Failed with status code $response"
            return 1
        fi
    done
}

# Send mail
send_mail() {
    local subject="$1"
    local body="$2"
    local status_code

    # Combine the list of recipients for the To: field
    TO_FIELD=$(IFS=, ; echo "${RECIPIENT_EMAIL[*]}")

    # Prepare the --mail-rcpt options for each recipient
    MAIL_RCPT_OPTIONS=()
    for email in "${RECIPIENT_EMAIL[@]}"; do
        MAIL_RCPT_OPTIONS+=(--mail-rcpt "$email")
    done

    # Set up email headers
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


# Main script execution
check_primary_cc_availability
primary_cc_status=$?

if [[ "$primary_cc_status" -ne 0 ]]; then
    send_mail "Cyber Controller Error: Certificate Renewal Issue" \
    "It appears that the Cyber Controller managing the ACME client is down and unable to renew the Alteon certificates.<br>This message was sent from the secondary Cyber Controller."
else
    echo "Primary Cyber Controller is available"
fi


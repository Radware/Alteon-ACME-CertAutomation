#!/bin/bash

# SMTP Configuration
SMTP_SERVER="smtp.office365.com:587"
SENDER_EMAIL="sender_email@company.com"
RECIPIENT_EMAIL=("recipient@company.com")
# Example of multiple recipients:
# RECIPIENT_EMAIL=("recipient1@company.com" "recipient2@company.com" "recipient3@company.com")
SENDER_PASSWORD="${sender_password_for_ACME:-}"
PROXY="${https_proxy:-}"

# Directory Paths
CURRENT_DIR="$(dirname "$(readlink -f "$0")")"
CERTS_STATUS_FILE="$CURRENT_DIR/certs_status.json"
DEHYDRATED_FILE="$CURRENT_DIR/dehydrated"
ALTEON_DEVICES_PER_DOMAINS_FILE="$CURRENT_DIR/alteon_devices_per_domains.json"

# Prepare certs_status.json
prepare_certs_status_file() {
    declare -A domains
  
    # Read each domains file defined in the JSON input file
    for domains_file in $(jq -r 'keys[]' "$ALTEON_DEVICES_PER_DOMAINS_FILE"); do
        input_file="$CURRENT_DIR/$domains_file"
  
        # Ensure the file exists before reading it
        if [ -f "$input_file" ]; then
            while IFS= read -r line; do
                # Remove alias part after '>' and trim leading/trailing whitespace
                line="${line%%>*}"
                line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')  # Trim whitespace
  
                # Skip empty lines and comments
                [[ -z "$line" || "$line" =~ ^# ]] && continue
                
                # Add each domain to the associative array with an empty status
                for domain in $line; do
                    domains["$domain"]=""
                done
            done < "$input_file"
        fi
    done
  
    # Write the domains to the output JSON file
    {
      echo "{"
      for key in "${!domains[@]}"; do
        echo "\"$key\": \"\","
      done | sed '$s/,$//'
      echo "}"
    } > "$CERTS_STATUS_FILE"
}


# Load certs status
load_certs_status() {
    cat "$CERTS_STATUS_FILE"
}

# Create HTML table
create_html_table() {
    local certs_status_file="$1"
    local table_html="<table border=\"1\"><tr><th>Domain</th><th>Status</th></tr>"
  
    while read -r domain status; do
        # Default status to "Failed" if it's empty
        [ -z "$status" ] && status="Failed"
        # Determine color based on status
        if [[ "$status" == *"Success"* ]]; then
            color="green"
        elif [[ "$status" == *"Unchanged"* ]]; then
            color="black"
        else
            color="red"
        fi
        table_html+="<tr><td>${domain}</td><td style=\"color: $color;\">${status}</td></tr>"
    done < <(jq -r 'to_entries[] | "\(.key) \(.value)"' "$certs_status_file")
  
    table_html+="</table>
    <p>For more information, please view the following logs:
    <br>
    <br>Cyber Controller CLI (root) - <b>/var/log/Alteon-ACME-CertAutomation_last_run.log</b> - describes the ACME flow.
    <br>Cyber Controller GUI - <b>&lt;cyber-controller-address:2189&gt/ui/#/app/administration/serverLogs</b> -
    describes the flow of creating and deleting the ACME HTTP challenge, as well as deploying certificates on the ADCs.</p>"
    echo "$table_html"
}

# Determine email subject
determine_subject() {
    local certs_status_file="$1"
    local statuses
    statuses=$(jq -r '.[]' "$certs_status_file" | sort -u)

    if [[ "$statuses" == "Unchanged" ]]; then
        echo "All certificates are unchanged"
    elif [[ "$statuses" =~ Success|Unchanged ]] && jq -e '.[] | select(. != "Success" and . != "Unchanged")' "$certs_status_file" > /dev/null; then
        echo "There is a failure while renewing the certificates"
    else
        echo "Cyber Controller successfully renewed the certificates"
    fi
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

# Main Execution

# Load alteon_devices_per_domains
alteon_devices_per_domains=$(jq -r 'keys[]' "$ALTEON_DEVICES_PER_DOMAINS_FILE")

# Prepare certs_status.json
prepare_certs_status_file

# Run dehydrated for each domain txt with the relevant Alteon devices
for domains_file in $alteon_devices_per_domains; do
    alteon_devices=$(jq -r --arg file "$domains_file" '.[$file]' "$ALTEON_DEVICES_PER_DOMAINS_FILE")
    export ALTEON_DEVICES="$alteon_devices"
    bash "$DEHYDRATED_FILE" -c -g --domains-txt "$domains_file"
done

# Load certificate status
certs_status=$(load_certs_status)

# Determine email subject and create HTML table
subject=$(determine_subject "$CERTS_STATUS_FILE")
html_table=$(create_html_table "$CERTS_STATUS_FILE")

# Send email

# Check sender password
if [ -z "$SENDER_PASSWORD" ]; then
    echo "Error: sender password is not set."
    exit 1
fi

echo "Sending an email..."
send_mail "$subject" "$html_table"

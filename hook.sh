#!/usr/bin/env bash

# Primary Cyber Controller parameters
PRIMARY_VDIRECT_IP_PORT="10.0.0.100:2189"
PRIMARY_VDIRECT_USER="root"
PRIMARY_VDIRECT_PASS="${primary_cc_password_for_ACME}"

# Secondary Cyber Controller parameters (Optional)
SECONDARY_VDIRECT_IP_PORT=""
SECONDARY_VDIRECT_USER=""
SECONDARY_VDIRECT_PASS="" #"${secondary_cc_password_for_ACME}"

INSECURE=true
ALTEONS=${ALTEON_DEVICES}


JSON_FILE_CERTS_STATUS="$(pwd)/certs_status.json"

# Check if --insecure should be used
CURL_OPTIONS=""
if [ "$INSECURE" = true ]; then
  CURL_OPTIONS="--insecure"
fi


function deploy_challenge {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    echo "TOKEN KEY ----> $TOKEN_FILENAME"
    echo "TOKEN VALUE --> $TOKEN_VALUE"

    # Convert ALTEONS to JSON array
    IFS=',' read -ra ADDR <<< "$ALTEONS"
    ALTEONS_JSON=""
    for i in "${ADDR[@]}"; do
        ALTEONS_JSON+="{\"type\": \"Adc\", \"name\": \"$i\"},"
    done
    ALTEONS_JSON="[${ALTEONS_JSON%,}]"

    # Prepare the JSON payload
    read -r -d '' DATA <<EOF
{
  "__dryRun": false,
  "alteons": $ALTEONS_JSON,
  "TOKEN_FILENAME": "${TOKEN_FILENAME}",
  "TOKEN_VALUE": "${TOKEN_VALUE}"
}
EOF

    # Function to perform curl request for challenge deployment
    perform_challenge_curl() {
        local url=$1
        local username=$2
        local password=$3
        curl -s -o /dev/null -w "%{http_code}" -u $username:$password "https://$url/api/runnable/ConfigurationTemplate/Alteon_Deploy_ACME_Challenge.vm/run/sync" \
          -H "Content-Type: application/json" \
          --data "$DATA" $CURL_OPTIONS
    }

    # Array of URLs and their respective credentials
    urls_credentials=("$PRIMARY_VDIRECT_IP_PORT $PRIMARY_VDIRECT_USER $PRIMARY_VDIRECT_PASS" "$SECONDARY_VDIRECT_IP_PORT $SECONDARY_VDIRECT_USER $SECONDARY_VDIRECT_PASS")

    # Attempt to use each URL up to 3 times
    max_attempts=3
    for entry in "${urls_credentials[@]}"; do
        read url username password <<< "$entry"
        if [ -n "$url" ]; then
            attempt=0
            while [ $attempt -lt $max_attempts ]; do
                attempt=$((attempt+1))
                response_code=$(perform_challenge_curl "$url" "$username" "$password")

                if [ "$response_code" -eq 200 ]; then
                    echo "Attempt $attempt: Successful response received from $url for challenge deployment"
                    break 2 # Exit both loops on success
                else
                    echo "Attempt $attempt: Failed with response code $response_code"
                fi

                if [ $attempt -eq $max_attempts ]; then
                    echo "Failed to get a successful response from $url after $max_attempts attempts for challenge deployment"
                fi

                # Optional: Add a delay between attempts
                sleep 1
            done
        fi
    done

    # Check if the final attempt failed
    if [ "$response_code" -ne 200 ]; then
        if [ -n "$SECONDARY_VDIRECT_IP_PORT" ]; then
            echo "Failed deploying challenge on Alteons - both cyber-controllers did not return 200 OK"
        else
            echo "Failed deploying challenge on Alteons, the first cyber-controller did not return 200 OK, and no secondary cyber-controller configured"
        fi
        exit 1
    else
        echo "Challenge has been successfully deployed."
    fi
    sleep 10
}


function clean_challenge {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    # This hook is called after attempting to validate each domain,
    # whether or not validation was successful. Here you can delete
    # files or DNS records that are no longer needed.
    #
    # The parameters are the same as for deploy_challenge.

    # Convert ALTEONS to JSON array
    IFS=',' read -ra ADDR <<< "$ALTEONS"
    ALTEONS_JSON=""
    for i in "${ADDR[@]}"; do
        ALTEONS_JSON+="{\"type\": \"Adc\", \"name\": \"$i\"},"
    done
    ALTEONS_JSON="[${ALTEONS_JSON%,}]"

    # Prepare the JSON payload
    read -r -d '' DATA <<EOF
{
  "__dryRun": false,
  "alteons": $ALTEONS_JSON,
  "TOKEN_FILENAME": "${TOKEN_FILENAME}"
}
EOF

    # Function to perform curl request for challenge deployment
    perform_challenge_curl() {
        local url=$1
        local username=$2
        local password=$3
        curl -s -o /dev/null -w "%{http_code}" -u $username:$password "https://$url/api/runnable/ConfigurationTemplate/Alteon_Clean_ACME_Challenge.vm/run/sync" \
          -H "Content-Type: application/json" \
          --data "$DATA" $CURL_OPTIONS
    }

    # Array of URLs and their respective credentials
    urls_credentials=("$PRIMARY_VDIRECT_IP_PORT $PRIMARY_VDIRECT_USER $PRIMARY_VDIRECT_PASS" "$SECONDARY_VDIRECT_IP_PORT $SECONDARY_VDIRECT_USER $SECONDARY_VDIRECT_PASS")

    # Attempt to use each URL up to 3 times
    max_attempts=3
    for entry in "${urls_credentials[@]}"; do
        read url username password <<< "$entry"
        if [ -n "$url" ]; then
            attempt=0
            while [ $attempt -lt $max_attempts ]; do
                attempt=$((attempt+1))
                response_code=$(perform_challenge_curl "$url" "$username" "$password")

                if [ "$response_code" -eq 200 ]; then
                    echo "Attempt $attempt: Successful response received from $url for cleaning challenge"
                    break 2 # Exit both loops on success
                else
                    echo "Attempt $attempt: Failed with response code $response_code"
                fi

                if [ $attempt -eq $max_attempts ]; then
                    echo "Failed to get a successful response from $url after $max_attempts attempts for cleaning challenge"
                fi

                # Optional: Add a delay between attempts
                sleep 1
            done
        fi
    done

    # Check if the final attempt failed
    if [ "$response_code" -ne 200 ]; then
        if [ -n "$SECONDARY_VDIRECT_IP_PORT" ]; then
            echo "Failed cleaning challenge from Alteons - both cyber-controllers did not return 200 OK"
        else
            echo "Failed cleaning challenge from Alteons, the first cyber-controller did not return 200 OK, and no secondary cyber-controller configured"
        fi
        exit 1
    else
        echo "Challenge has been successfully cleaned."
    fi
}


function deploy_cert {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"

    KEY_CONTENT=$(cat ${KEYFILE} | sed ':a;N;$!ba;s/\n/\\n/g')
    CERT_CONTENT=$(cat ${CERTFILE} | sed ':a;N;$!ba;s/\n/\\n/g')
    CHAIN_CONTENT=$(cat ${CHAINFILE} | sed ':a;N;$!ba;s/\n/\\n/g')

    # echo $KEY_CONTENT
    # echo $CERT_CONTENT
    # echo $CHAIN_CONTENT

    # Avoid * in the Alteon certificate name because this is a special character
    if [[ ${DOMAIN:0:1} == "*" ]]; then
        # Replace * with wildcard-cert
        ALTEON_CERT_NAME="wildcard-cert${DOMAIN:1}"
    else
        ALTEON_CERT_NAME=$DOMAIN
    fi

    # Convert ALTEONS to JSON array
    IFS=',' read -ra ADDR <<< "$ALTEONS"
    ALTEONS_JSON=""
    for i in "${ADDR[@]}"; do
        ALTEONS_JSON+="{\"type\": \"Adc\", \"name\": \"$i\"},"
    done
    ALTEONS_JSON="[${ALTEONS_JSON%,}]"

    # Prepare the JSON payload
    read -r -d '' DATA <<EOF
{
  "__dryRun": false,
  "alteons": $ALTEONS_JSON,
  "name": "${ALTEON_CERT_NAME}",
  "key": "${KEY_CONTENT}",
  "password": "",
  "srvrcert": "${CERT_CONTENT}",
  "intermca": "${CHAIN_CONTENT}"
}
EOF

    # Function to perform curl request
    perform_curl() {
        local url=$1
        local username=$2
        local password=$3
        curl -s -o /dev/null -w "%{http_code}" -u $username:$password "https://$url/api/runnable/ConfigurationTemplate/Alteon_Deploy_Certificate.vm/run/sync" \
          -H "accept: application/json, text/plain, */*" \
          -H "accept-language: en-US,en;q=0.9" \
          -H "content-type: application/json" \
          -H "sec-ch-ua: \"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"" \
          -H "sec-ch-ua-mobile: ?0" \
          -H "sec-ch-ua-platform: \"Windows\"" \
          -H "sec-fetch-dest: empty" \
          -H "sec-fetch-mode: cors" \
          -H "sec-fetch-site: same-origin" \
          -H "user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36" \
          $CURL_OPTIONS \
          --data "$DATA"
    }

    # Array of URLs and their respective credentials
    urls_credentials=("$PRIMARY_VDIRECT_IP_PORT $PRIMARY_VDIRECT_USER $PRIMARY_VDIRECT_PASS" "$SECONDARY_VDIRECT_IP_PORT $SECONDARY_VDIRECT_USER $SECONDARY_VDIRECT_PASS")

    # Attempt to use each URL up to 3 times
    max_attempts=3
    for entry in "${urls_credentials[@]}"; do
        read url username password <<< "$entry"
        if [ -n "$url" ]; then
            attempt=0
            while [ $attempt -lt $max_attempts ]; do
                attempt=$((attempt+1))
                response_code=$(perform_curl "$url" "$username" "$password")

                if [ "$response_code" -eq 200 ]; then
                    echo "Attempt $attempt: Successful response received from $url"
                    break 2 # Exit both loops on success
                else
                    echo "Attempt $attempt: Failed with response code $response_code"
                fi

                if [ $attempt -eq $max_attempts ]; then
                    echo "Failed to get a successful response from $url after $max_attempts attempts"
                fi

                # Optional: Add a delay between attempts
                sleep 1
            done
        fi
    done

    # Check if the final attempt failed
    if [ "$response_code" -ne 200 ]; then
        if [ -n "$SECONDARY_VDIRECT_IP_PORT" ]; then
            echo "Failed deploying cert on Alteons - both cyber-controllers did not return 200 OK"
        else
            echo "Failed deploying cert on Alteons, the first cyber-controller did not return 200 OK, and no secondary cyber-controller configured"
        fi
        exit 1
    else
        echo "Certificate deployment succeeded."
    fi

    echo "Cert file is ${CERTFILE}"

    SANs=$(openssl x509 -in "${CERTFILE}" -noout -text | grep -oP '(?<=DNS:)[^,]*')
    for DOMAIN_FROM_CERT in $SANs; do
        jq --arg domain "$DOMAIN_FROM_CERT" --arg value "Success" '. + {($domain): $value}' "$JSON_FILE_CERTS_STATUS" > "$JSON_FILE_CERTS_STATUS.tmp" && mv "$JSON_FILE_CERTS_STATUS.tmp" "$JSON_FILE_CERTS_STATUS"
    done
}


function unchanged_cert {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

    # This hook is called once for each certificate that is still
    # valid and therefore wasn't reissued.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
}

invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"

    # This hook is called if the challenge response has failed, so domain
    # owners can be aware and act accordingly.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - RESPONSE
    #   The response that the verification server returned
}

request_failure() {
    local STATUSCODE="${1}" REASON="${2}" REQTYPE="${3}"

    # This hook is called when a HTTP request fails (e.g., when the ACME
    # server is busy, returns an error, etc). It will be called upon any
    # response code that does not start with '2'. Useful to alert admins
    # about problems with requests.
    #
    # Parameters:
    # - STATUSCODE
    #   The HTML status code that originated the error.
    # - REASON
    #   The specified reason for the error.
    # - REQTYPE
    #   The kind of request that was made (GET, POST...)
}

exit_hook() {
  # This hook is called at the end of a dehydrated command and can be used
  # to do some final (cleanup or other) tasks.

  :
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|exit_hook)$ ]]; then
  "$HANDLER" "$@"
fi


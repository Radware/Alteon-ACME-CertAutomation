#!/usr/bin/env bash

# Primary Cyber Controller parameters
PRIMARY_CC_IP="10.0.0.100"
PRIMARY_CC_USER="ACME-User"
PRIMARY_CC_PASS="${primary_cc_password_for_ACME}"

# Secondary Cyber Controller parameters (Optional)
SECONDARY_CC_IP=""
SECONDARY_CC_USER=""
SECONDARY_CC_PASS="" #"${secondary_cc_password_for_ACME}"

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
    perform_curl() {
        local CC_IP=$1
        local username=$2
        local password=$3
        local temp_response

        echo "Logging in to Cyber-Controller"
        CC_JSESSION=$(curl -s -X POST "https://$CC_IP/mgmt/system/user/login" -H 'Content-Type: application/json' --data '{"username": "'"$username"'", "password": "'"$password"'"}' $CURL_OPTIONS | jq -r '.jsessionid')

        echo "CC_JSESSION is:"
        echo $CC_JSESSION

        # Capture both response body and status code
        temp_response=$(curl -s -w "%{http_code}" "https://$CC_IP:2189/api/runnable/ConfigurationTemplate/Alteon_Deploy_ACME_Challenge.vm/run/sync" \
            -H "content-type: application/json" \
            -b "JSESSIONID=$CC_JSESSION" \
            $CURL_OPTIONS \
            --data "$DATA")

        # Extract the status code and response body
        RESPONSE_BODY="${temp_response::-3}" # Remove the last 3 characters (status code)
        RESPONSE_CODE="${temp_response: -3}" # Extract the last 3 characters (status code)

        if [ -n "$CC_JSESSION" ]; then
            echo "Logging out from Cyber-Controller"
            curl "https://$CC_IP/mgmt/system/user/logout" \
                -H 'content-type: application/json;charset=UTF-8' \
                -b "JSESSIONID=$CC_JSESSION" \
                --data-raw '{"headers":{"Content-Type":"application/json","Cache-Control":"no-cache"}}' \
                $CURL_OPTIONS
        fi
    }

    # Array of URLs and their respective credentials
    urls_credentials=("$PRIMARY_CC_IP $PRIMARY_CC_USER $PRIMARY_CC_PASS" "$SECONDARY_CC_IP $SECONDARY_CC_USER $SECONDARY_CC_PASS")

    # Attempt to use each URL up to 3 times
    max_attempts=3
    for entry in "${urls_credentials[@]}"; do
        read CC_IP username password <<< "$entry"
        if [ -n "$CC_IP" ]; then
            attempt=0
            while [ $attempt -lt $max_attempts ]; do
                attempt=$((attempt+1))
                perform_curl "$CC_IP" "$username" "$password"
                # echo $response | jq -r .

                echo "response_code $RESPONSE_CODE"


                if [[ "$RESPONSE_CODE" -eq 200 ]]; then
                    echo "Attempt $attempt: Successful response received from $CC_IP"

                    break 2 # Exit both loops on success

                else
                    echo "Attempt $attempt: Failed with response code ${RESPONSE_CODE:-unknown}"
                    echo "$RESPONSE_BODY"
                fi

                if [ $attempt -eq $max_attempts ]; then
                    echo "Failed to get a successful response from $CC_IP after $max_attempts attempts"
                fi

                # Optional: Add a delay between attempts
                sleep 10
            done
        fi
    done

    # Check if the final attempt failed
    if [[ $RESPONSE_CODE -ne 200 ]]; then
        if [ -n "$SECONDARY_CC_IP" ]; then
            echo "Failed cleaning challenge from Alteons - both cyber-controllers did not return 200 OK"
        else
            echo "Failed cleaning challenge from Alteons, the first cyber-controller did not return 200 OK, and no secondary cyber-controller configured"
        fi

    else
        echo "Challenge has been successfully deployed"
    fi
    sleep 5
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


    perform_curl() {
        local CC_IP=$1
        local username=$2
        local password=$3
        local temp_response

        echo "Logging in to Cyber-Controller"
        CC_JSESSION=$(curl -s -X POST "https://$CC_IP/mgmt/system/user/login" -H 'Content-Type: application/json' --data '{"username": "'"$username"'", "password": "'"$password"'"}' $CURL_OPTIONS | jq -r '.jsessionid')

        echo "CC_JSESSION is:"
        echo $CC_JSESSION

        # Capture both response body and status code
        temp_response=$(curl -s -w "%{http_code}" "https://$CC_IP:2189/api/runnable/ConfigurationTemplate/Alteon_Clean_ACME_Challenge.vm/run/sync" \
            -H "content-type: application/json" \
            -b "JSESSIONID=$CC_JSESSION" \
            $CURL_OPTIONS \
            --data "$DATA")

        # Extract the status code and response body
        RESPONSE_BODY="${temp_response::-3}" # Remove the last 3 characters (status code)
        RESPONSE_CODE="${temp_response: -3}" # Extract the last 3 characters (status code)

        if [ -n "$CC_JSESSION" ]; then
            echo "Logging out from Cyber-Controller"
            curl "https://$CC_IP/mgmt/system/user/logout" \
                -H 'content-type: application/json;charset=UTF-8' \
                -b "JSESSIONID=$CC_JSESSION" \
                --data-raw '{"headers":{"Content-Type":"application/json","Cache-Control":"no-cache"}}' \
                $CURL_OPTIONS
        fi
    }

    # Array of URLs and their respective credentials
   urls_credentials=("$PRIMARY_CC_IP $PRIMARY_CC_USER $PRIMARY_CC_PASS" "$SECONDARY_CC_IP $SECONDARY_CC_USER $SECONDARY_CC_PASS")

   # Attempt to use each URL up to 3 times
   max_attempts=3
   for entry in "${urls_credentials[@]}"; do
       read CC_IP username password <<< "$entry"
       if [ -n "$CC_IP" ]; then
           attempt=0
           while [ $attempt -lt $max_attempts ]; do
               attempt=$((attempt+1))
               perform_curl "$CC_IP" "$username" "$password"
               # echo $response | jq -r .

               echo "response_code $RESPONSE_CODE"


               if [[ "$RESPONSE_CODE" -eq 200 ]]; then
                   echo "Attempt $attempt: Successful response received from $CC_IP"

                   break 2 # Exit both loops on success

               else
                   echo "Attempt $attempt: Failed with response code ${RESPONSE_CODE:-unknown}"
                   echo "$RESPONSE_BODY"
               fi

               if [ $attempt -eq $max_attempts ]; then
                   echo "Failed to get a successful response from $CC_IP after $max_attempts attempts"
               fi

               # Optional: Add a delay between attempts
               sleep 10
           done
       fi
   done

   # Check if the final attempt failed
   if [[ $RESPONSE_CODE -ne 200 ]]; then
       if [ -n "$SECONDARY_CC_IP" ]; then
           echo "Failed cleaning challenge from Alteons - both cyber-controllers did not return 200 OK"
       else
           echo "Failed cleaning challenge from Alteons, the first cyber-controller did not return 200 OK, and no secondary cyber-controller configured"
       fi

   else
       echo "Challenge has been successfully cleaned"
   fi
   sleep 5
}


function deploy_cert {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"

    KEY_CONTENT=$(cat ${KEYFILE} | sed ':a;N;$!ba;s/\n/\\n/g')
    CERT_CONTENT=$(cat ${CERTFILE} | sed ':a;N;$!ba;s/\n/\\n/g')
    CHAIN_CONTENT=$(cat ${CHAINFILE} | sed ':a;N;$!ba;s/\n/\\n/g')

    # echo $KEY_CONTENT
    # echo $CERT_CONTENT
    # echo $CHAIN_CONTENT

    # Get the serial number of the cert
    SERIAL_NEW_CERT=$(openssl x509 -in ${CERTFILE} -noout -serial | cut -d'=' -f2)
    echo "SERIAL_NEW_CERT $SERIAL_NEW_CERT"

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
  "serialNewCert": "${SERIAL_NEW_CERT}",
  "name": "${ALTEON_CERT_NAME}",
  "key": "${KEY_CONTENT}",
  "password": "",
  "srvrcert": "${CERT_CONTENT}",
  "intermca": "${CHAIN_CONTENT}"
}
EOF


    # Function to perform curl request
    perform_curl() {
        local CC_IP=$1
        local username=$2
        local password=$3
        local temp_response

        echo "Logging in to Cyber-Controller"
        CC_JSESSION=$(curl -s -X POST "https://$CC_IP/mgmt/system/user/login" -H 'Content-Type: application/json' --data '{"username": "'"$username"'", "password": "'"$password"'"}' $CURL_OPTIONS | jq -r '.jsessionid')

        echo "CC_JSESSION is:"
        echo $CC_JSESSION

        # Capture both response body and status code
        temp_response=$(curl -s -w "%{http_code}" "https://$CC_IP:2189/api/runnable/ConfigurationTemplate/Alteon_Deploy_Certificate.vm/run/sync" \
            -H "content-type: application/json" \
            -b "JSESSIONID=$CC_JSESSION" \
            $CURL_OPTIONS \
            --data "$DATA")

        # Extract the status code and response body
        RESPONSE_BODY="${temp_response::-3}" # Remove the last 3 characters (status code)
        RESPONSE_CODE="${temp_response: -3}" # Extract the last 3 characters (status code)

        if [ -n "$CC_JSESSION" ]; then
            echo "Logging out from Cyber-Controller"
            curl "https://$CC_IP/mgmt/system/user/logout" \
                -H 'content-type: application/json;charset=UTF-8' \
                -b "JSESSIONID=$CC_JSESSION" \
                --data-raw '{"headers":{"Content-Type":"application/json","Cache-Control":"no-cache"}}' \
                $CURL_OPTIONS
        fi
    }

    # Array of URLs and their respective credentials
    urls_credentials=("$PRIMARY_CC_IP $PRIMARY_CC_USER $PRIMARY_CC_PASS" "$SECONDARY_CC_IP $SECONDARY_CC_USER $SECONDARY_CC_PASS")

    # Attempt to use each URL up to 3 times
    max_attempts=3
    for entry in "${urls_credentials[@]}"; do
        read CC_IP username password <<< "$entry"
        if [ -n "$CC_IP" ]; then
            attempt=0
            while [ $attempt -lt $max_attempts ]; do
                attempt=$((attempt+1))
                perform_curl "$CC_IP" "$username" "$password"
                # echo $response | jq -r .

                echo "response_code $RESPONSE_CODE"


                if [[ "$RESPONSE_CODE" -eq 200 ]]; then
                    echo "Attempt $attempt: Successful response received from $CC_IP"

                    if [ -z "$cert_status" ]; then
                        cert_status=$(echo "$RESPONSE_BODY" | jq -r '.parameters.output // "No output key found"')
                        echo $cert_status
                    fi

                    break 2 # Exit both loops on success

                else
                    echo "Attempt $attempt: Failed with response code ${RESPONSE_CODE:-unknown}"
                    echo "$RESPONSE_BODY"
                fi

                if [ $attempt -eq $max_attempts ]; then
                    echo "Failed to get a successful response from $CC_IP after $max_attempts attempts"
                fi

                # Optional: Add a delay between attempts
                sleep 10
            done
        fi
    done

    # Check if the final attempt failed
    if [[ $RESPONSE_CODE -ne 200 ]]; then
        if [ -n "$SECONDARY_CC_IP" ]; then
            echo "Failed deploying cert on Alteons - both cyber-controllers did not return 200 OK"
        else
            echo "Failed deploying cert on Alteons, the first cyber-controller did not return 200 OK, and no secondary cyber-controller configured"
        fi
    else
        echo "Certificate deployment succeeded."
    fi

    echo "Cert file is ${CERTFILE}"

    SANs=$(openssl x509 -in "${CERTFILE}" -noout -text | grep -oP '(?<=DNS:)[^,]*')
    for DOMAIN_FROM_CERT in $SANs; do
        jq --arg domain "$DOMAIN_FROM_CERT" --arg value "$cert_status" '. + {($domain): $value}' "$JSON_FILE_CERTS_STATUS" > "$JSON_FILE_CERTS_STATUS.tmp" && mv "$JSON_FILE_CERTS_STATUS.tmp" "$JSON_FILE_CERTS_STATUS"

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

    deploy_cert "$DOMAIN" "$KEYFILE" "$CERTFILE" "$FULLCHAINFILE" "$CHAINFILE"

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

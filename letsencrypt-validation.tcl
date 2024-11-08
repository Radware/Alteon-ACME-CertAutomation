when HTTP_REQUEST {
    if {[HTTP::path] starts_with "/.well-known/acme-challenge/"} {
        set token [lindex [split [HTTP::path] "/"] end]
        set response [class match -value -- $token equals acme_responses]
        if { "$response" == "" } {
            log "Responding with 404 to ACME challenge $token"
            HTTP::respond 404 content "Challenge-response token not found."
        } else {
            log "Responding to ACME challenge $token with response $response"
            HTTP::respond 200 content "$response" "Content-Type" "text/plain; charset=utf-8"
        }
    }
}
-----END
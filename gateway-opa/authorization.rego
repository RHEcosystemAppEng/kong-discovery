package kongdemo

import future.keywords

# By default, deny requests.
default allow := false

allow if {
    [_, payload, _] := io.jwt.decode(substring(input.request.http.headers["authorization"], 7, -1))
    some role in payload.roles
    role == "customer"
}

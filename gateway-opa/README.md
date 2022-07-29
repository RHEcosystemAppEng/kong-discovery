# Gateway integration with Keycloak and OPA

This document describes how to integrate Kong Gateway with Keycloak for OIDC Authentication and OPA for
authorization.

Keycloak will be responsible for performing the OIDC Authentication and returing a JWT token that
will be propagated in to the upstream service.

Then we will use an OPA policy to perform Authorization by decoding the JWT token and deciding whether it is
a `customer` or not.

## Install

We will be following part of the instructions described in the [Gateway Plugins](../gateway-plugins/README.md) document.

[Install the Kong Gateway with the Kubernetes Ingress Controller](../gateway-plugins/README.md#install-kong-gateway---all-in-one-db-full).
[Install Keycloak](../gateway-plugins/README.md#keycloak)

### Install the Open Policy Agent

Create the `kong-opa` namespace

```bash
oc create ns kong-opa
```

Now create a configmap with the policies

```bash
oc create cm authn-policies --from-file=gateway-opa/authorization.rego -n kong-opa
```

The Policy we are going to use is as explained below:

```yaml
package kongdemo

import future.keywords

# By default, deny requests.
default allow := false

allow if {
    [_, payload, _] := io.jwt.decode(substring(input.request.http.headers["authorization"], 7, -1))
    some role in payload.roles
    role == "customer"
}
```

It will take the `authorization` header and remove the `Bearer: ` part to decode the JWT token.
Then it will traverse the roles and check that it contains the `customer` role.

Finally deploy the OPA Server

```bash
oc apply -f gateway-opa/deploy-opa.yaml
```

### Install the Magnanimo app

```bash
oc create ns kuma-app
oc apply -f gateway-multizone/magnanimo.yaml
```

### Expose the Magnanimo app

```bash
oc apply -f gateway-opa/ingress.yaml
```

Validate the service is working through the proxy

```bash
http `oc get route kong-kong-proxy -n kong --template='{{ .spec.host }}'`/magnanimo       
HTTP/1.1 200 OK
cache-control: private
content-length: 22
content-type: text/html; charset=utf-8
date: Fri, 29 Jul 2022 15:40:06 GMT
server: Werkzeug/1.0.1 Python/3.8.3
set-cookie: 157c7d417676c54695fa6cf886b2feeb=eaee7aaac681437e37a61f18a4eccd92; path=/; HttpOnly
via: kong/2.8.1.2-enterprise-edition
x-kong-proxy-latency: 1
x-kong-upstream-latency: 1

Hello World, Magnanimo
```

## Authentication

Let's install the openidc plugin.

```bash
OCP_DOMAIN=`oc get ingresses.config/cluster -o jsonpath={.spec.domain}`
sed -e "s/\${i}/1/" -e "s/\$OCP_DOMAIN/$OCP_DOMAIN/" ./gateway-opa/openidc-keycloak-plugin.yaml | kubectl apply -f -
```

And let's annotate the service to make use of the plugin.

```bash
oc annotate svc magnanimo -n kuma-app konghq.com/plugins=keycloak-auth-plugin
```

Try to do the same request and you should be redirected to the SSO

```bash
$ http `oc get route kong-kong-proxy -n kong --template='{{ .spec.host }}'`/magnanimo
HTTP/1.1 302 Moved Temporarily
cache-control: no-store
content-length: 0
date: Fri, 29 Jul 2022 15:44:41 GMT
location: https://keycloak-kong-keycloak.apps.ruben.pgv5.p1.openshiftapps.com/auth/realms/kong/protocol/openid-connect/auth?client_id=kuma-demo-client&code_challenge_method=S256&code_challenge=VrLLV5ibuBDNPtwpRBdbbrcZK3DGsgtCzYKpMJ1w5go&scope=openid&redirect_uri=http%3A%2F%2Fkong-kong-proxy-kong.apps.ruben.pgv5.p1.openshiftapps.com%2Fmagnanimo&nonce=WB0eUFPvfBP4sRSRLgiTHUHT&state=GH4hrA4vY80VcxRj60tTY32X&response_mode=query&response_type=code
server: kong/2.8.1.2-enterprise-edition
set-cookie: authorization=YAeAvbb0OWUvcIMMcoTn7Q|1659110081|rKQSv34wH6WnziDte4_j0xhXmlhEWPnHNym6iKviwDW5dhFIAvbgEjcTYdp05SndxpgIsh3Oo_vLUXf6rLdX91NBwc77Z7aKptjoRwQL972lOqVTUyeppXJJOE1N7l-hj3fiwEnomyiLOZm17_jvnUnNHRpTHkSgKbBmRgeZvgekngTkExfOhJqmd9a5t7Rka6DbiP-DliLrL4zmdTDn_teRfP9UU_pvnOYkdRQHH7wra7xWetrkZCZ2AsX_F7IBngdd7Go_0qSceIDQ6FCd7GufruTNlTwU2HdwRpTptg91iUzThLnMHbta5AmmbM3m|RaCpIJDNyCsihsxWJKw-C2ZaN1M; Path=/; HttpOnly
set-cookie: 157c7d417676c54695fa6cf886b2feeb=eaee7aaac681437e37a61f18a4eccd92; path=/; HttpOnly
x-kong-response-latency: 53
```

Now let's retrieve a token:

```bash
token=$(http --verify=no -f https://`oc get routes -n kong-keycloak keycloak --template={{.spec.host}} `/auth/realms/kong/protocol/openid-connect/token client_id=kuma-demo-client grant_type=password username=bob password=kong client_secret=client-secret | jq -r .access_token)
```

And use it in the request

```bash
$ http `oc get route kong-kong-proxy -n kong --template='{{ .spec.host }}'`/magnanimo -A bearer --auth $token   
HTTP/1.1 200 OK
cache-control: private
content-length: 22
content-type: text/html; charset=utf-8
date: Fri, 29 Jul 2022 15:47:15 GMT
server: Werkzeug/1.0.1 Python/3.8.3
set-cookie: session=tvvHGrY-e00efInvKY63Xw|1659113235|rhYMKGQz7U7Z0Kp0um6jhth2yZSi7wx8Rwd_GS0deXhY6LN692Hp6dxd0DxIOY8AjiH0parMGWAvzThenssju9md8FVL9a0edDw4z9nCgMyOG1NJ7UVj3l9k3Q3k3NU41EsgGESNM5UJlJ20GSY6NjJcuAtLOuGtH08KwNfvQtXUaEEPr9tOC9ecrVVMvUkzPJwLJjK2YUO7bfkfcphUVtzqWhyitn6PkNNlY3kgwExsGgBucP0OI1XbexbNJzSXeNZK7a0orU2MOWaCOvNuXnu8VazOR7vgfVftY1ALWxhEwKPuP1f2TdEggkIq6gvE_E-V6rCoRstJqhct5tLcsb7hX0i6Dv62k0P2yDmAlkfkI4U0G6EC2ccCaQhfqK_KEpYBmAabdpagHGLmDE7ftUwoAhCG_JVNxkkdnUKOPivR4X0w54nY97b9a0e19blNo1ruJhziKOj1CkccHZzUg46RuL6w_Y9S_LhwwAyrg1uOU-7GTJ2TiflQ8EWvYwAiJ8Ap1kirzHI-3t3DDudo4lJjXixYpo2vyFacW9-yHr60KGDIDmJVsVt-cFuz8jZsuOAWw7nwewNkDqkqRCD-ccF2KjRHJM_HVaPW9ls0a5CxfiTHa25n1BSJrgw15Y88AR2UKgiRD8gpji7gTmVeUK5zQCA4z-dF8Xd17MIuNl4NTgdDzN-Gz3AIoHQPSgsnHAJHkmdDmdpEcjvIgmviOnvAXPmThcYP70XrIWErr9ye28mZmpT55XqWCA0xRxWHPBK7RBsO_8HD0BzoZjzMgX_vb1k-xIuI7tpS6GYwEl1XlDZWEvQQgQx-2cFsaJpL1_-m0kQpZRImJpcrtdhcnwGQ4KX83M7LMVfhxXKqQ-cGOt5o_ic5iiYIiC1q073En_6F4-qsD3a1_XZjvCDutFbQgGCMBj3VkDd_LbLLEnkm7_N9inmeNkRK2sKjY5jvxqrCK54_GtYzmXciBWfuvxSbH-OkY4qtcdLO1VDYBk1qadGjV9qB9IxJLdeFZqDw0LltC0EtpO-HMotuO1KUaIZ_tG264lHEfIVXdYKEP0_E8H79YYLukfuqM-ovzYu_p8Iqm8H0UXrGYm62fUYD6APwQPdfrEKiNdeQlffa_MOxpPFUX7mx6Do0QU_P8XSCD5MEFDpJDTPhtJLF21Jc6sJ6SQbsegk7nvTtr0BuutJm5r6m7vlNuwnOM5ulojOEM9C5qhoUVoowdPlCGO0PF_x6MfFGtpyPsut2xk2AbB-_1gI5HECZO3i_-5agu7xuk2yxW71S5XljJ3chx-fpSuWMn7FxZwKp7VQFhiaAA3RlERFekiK9ndb6iKFLTYJm2xQ6gdrV1Tmbg8FD9Qdl7TWl8PawIK0xeYQnBJcRHvEe11OXfxl8TThj9x0xYnZjiOInd6HRrR0MDEAEEvoFIAuwMToOB9DqWWlz6vPkM2c|G1PCeVblnLHkCug88SHTLZS2Pzs; Path=/; SameSite=Lax; HttpOnly
set-cookie: 157c7d417676c54695fa6cf886b2feeb=eaee7aaac681437e37a61f18a4eccd92; path=/; HttpOnly
via: kong/2.8.1.2-enterprise-edition
x-kong-proxy-latency: 1
x-kong-upstream-latency: 2

Hello World, Magnanimo
```

## Authorization with OPA

If we decode the JWT token stored in `$token` we should see something like this in the payload:

```json
{
  "exp": 1659110344,
  "iat": 1659110044,
  "jti": "db5c4bec-d2e2-43e5-8edc-8a38b168d635",
  "iss": "https://keycloak-kong-keycloak.apps.ruben.pgv5.p1.openshiftapps.com/auth/realms/kong",
  "sub": "b26e18fc-32a5-4e9c-be13-fe5e4a676d74",
  "typ": "Bearer",
  "azp": "kuma-demo-client",
  "session_state": "324ac75d-85ea-4cd7-a079-72ea2564ef39",
  "scope": "",
  "sid": "324ac75d-85ea-4cd7-a079-72ea2564ef39",
  "preferred_username": "bob"
}
```

This is not a `customer` so we should not authorize this user.

Let's add the OPA Plugin to the picture. This Plugin has lower priority than the OIDC Plugin
so it should trigger after the authentication has taken place.

```bash
oc apply -f gateway-opa/opa-plugin.yaml -n kuma-app
```

And let's update the `magnanimo` service annotation

```bash
oc annotate svc magnanimo -n kuma-app konghq.com/plugins=keycloak-auth-plugin,opa-authorization-plugin --overwrite
```

Finally, let's check if the user can now access the service:

```bash
$ http `oc get route kong-kong-proxy -n kong --template='{{ .spec.host }}'`/magnanimo -A bearer --auth $token
HTTP/1.1 403 Forbidden
content-length: 26
content-type: application/json; charset=utf-8
date: Fri, 29 Jul 2022 15:56:50 GMT
server: kong/2.8.1.2-enterprise-edition
set-cookie: session=4tFOvtBpekrNkKrCOrywpw|1659113810|5I3bwbUkKh9i0UsYPrMI_pX5xv5RcXy7MeojjT-OVpo8cA50uR76ciYb2kr9k3PKJl5MjtrU7_HFW_IlvD9inJ1FwEqbE7U97s5zUzT4patHftZI5CKciOyGj_v_Fdv8Xi42bm-HHqn31Pw4TGpXIgIYQZ6gEPg4QV1tPO-RRUzG6Ago4dSEXfBNNHpTeQOfJLKZMjrr8NeXBn7kPuSXjmqPjMNG0dITy4t9nGqKVuT35fJSXOZyRhYC0G_uSWtmI9xq-t_BSO20jUABfG8BJqRKtoGtSp9vhJvqh3ojel9dgv8lYgJIXHfSIXHXLtpNiIKJmcmRni7FmcYJIyPyNoA2EDWHklkE4YOuG1nWreC2QIyfRqsjTq3dYDcOnx8tXE-7AsVvORwb-8Rws5msXQ545aEUNzb3pCrUAP-EQ9bMwdzo_j9fhevHcgbwOXGOmB0ZbvSINZfXOMvCxXK_W4vGduAu0yTcJaaPUSPmPT7ubwfkA872W9Uksb8gxjlNP2TV5CEd4TcchYaOCWIi1ou7g0KR8VxnkB2AhPfPQbW0t8wyUNHYJB6Rrv6fUl3EE9b-5tt05GEfcfJrMQkjMvW8-PH9FlLF-XL1Le_pRGBjguXSg8zzEkG3z5TDhBq2Iiq8_VWRI7-Nw_sMyilVOwN-SlUuW3Oog4Oiz-XSOFTS9j_ulUUqggmsckrrxBaEAcSigzo2pyhTVxCw2JJp8Ss7FVBCg_3c6YqaRxKpXWgH6ARjocmW7mNmxFxj17yLI0GUhHwqTYLW2MuD9ACezYY2oM7c7dDMf-EqjjtRGnv8kkuxDISU0xlElZGAF1wErqwSJiO12bhoNEPXn84CDKrwOjTKbGHD0go9j-_RuGBoQLnQMjK8sm-74EjVoKtxZvs-dY3MKMsP3g-yczp5OEuDBgepQUGI1Dc-43aytKuxGbin5EzOoc5YGDFcOwbjfwjjUtfYQgRwxZGlcViSu-1PzeBIEn051-aeKVhMXMhHJ5dldeOIQvQ1xotLs9WELnDzReUT_clanpBPz_z7tO6C7w1t7s9DUqgM8-J_HZdg2sGZwlyjuXiX1aEo7Kv0san_QwbdQ5NOiFnQc-FgG4yO8KdTuYbLO8RO8OYNVCaR6LBqgQKulnuM4bBaj3xCOK_qFtC3SX_o53V53Q6UjWKjZ_7Xl5I6VZhrGOIoHCHXHs62OOLI5JqQN7jpiNt_kRBuzutAkYcaHPmccSA1xchJc4I0eZV5g120vvExFCI5pLKOV0D45rDSxC_50s5yQAffdClrBgJVo0ZZFqzdRDWIHY5y7aVyB4p8Gl8nnGKEztuQWETkOPoRch0sB50GW6xG0C9EpGVyHhcVrFa6tKzrCTAybRpjddindqJ__sZHunTphqNuK5wc8pVOgXkw|ABA1pCLD4yqk1yNIfY8JOOiZJdE; Path=/; SameSite=Lax; HttpOnly
set-cookie: 157c7d417676c54695fa6cf886b2feeb=eaee7aaac681437e37a61f18a4eccd92; path=/; HttpOnly
x-kong-response-latency: 20

{
    "message": "unauthorized"
}
```

Sadly, the user is not a `customer` but there is another user who is:

```bash
token=$(http --verify=no -f https://`oc get routes -n kong-keycloak keycloak --template={{.spec.host}} `/auth/realms/kong/protocol/openid-connect/token client_id=kuma-demo-client grant_type=password username=kermit password=kong client_secret=client-secret | jq -r .access_token)
```

This is `kermit`'s JWT decoded:

```json
{
  "exp": 1659110614,
  "iat": 1659110314,
  "jti": "4d582b0b-a51d-42b4-918d-309cf152235f",
  "iss": "https://keycloak-kong-keycloak.apps.ruben.pgv5.p1.openshiftapps.com/auth/realms/kong",
  "sub": "196dcd4e-c978-41f3-b800-8074e6d6db77",
  "typ": "Bearer",
  "azp": "kuma-demo-client",
  "session_state": "43a8b205-d12a-4464-9c75-66905603994b",
  "scope": "",
  "sid": "43a8b205-d12a-4464-9c75-66905603994b",
  "roles": [
    "customer"
  ],
  "preferred_username": "kermit"
}
```

This is a `customer` so he should have access:

```bash
$ http `oc get route kong-kong-proxy -n kong --template='{{ .spec.host }}'`/magnanimo -A bearer --auth $token
HTTP/1.1 200 OK
cache-control: private
content-length: 22
content-type: text/html; charset=utf-8
date: Fri, 29 Jul 2022 15:59:37 GMT
server: Werkzeug/1.0.1 Python/3.8.3
set-cookie: session=k-cS1rIehGUG1plAGN4n9w|1659113977|fREdYamcBZu4p3A4meo9Th_Mcb13RiMJYZ3LvQx39IgIvsSRtoUM1LfIRy54QnmvkAgtLkBhkX27XGgJTRFkijNrb5hfFmqt5trlWBTCuU9wuKlbhptVBNxjyluoR0hToHO6QwcrB9YkTalYQNLnl_sG4nehsmjc6ICwOYPTA6cI2SeiIGY1IjLGa4eGbZ1rdHGZERQAcLKpH19ZL4iBSsGFF-a5bGzdWY6kvYfLivEbIibiQThW5kCi5GXiKjlINSgqLgS8qOD0X5SuOxOEeD8-VfoF-78NjtSLEA5hf4MT3SerHFHoZNwvV0UGrkO-x-V1ZsT_52APa_paxdIVeCKXvqeft2nurvhAw7Di8rUUUqJMZjncNIh_D1Zvvpn3LR98sE17KVuwPNzP-_8naK-NUugCY9VJCwefYTiMGTFGCapwSg4owqp1ISZ12aNGreZOYxwJrhgwSNfdxmnQYoDOVdN-Q-DpJoAvjt7utpMcDP-oqfSgQFBfaLJkXa-D9al1YBS7384nh4N4t17wAzKMuq0vHI98p5sGJ_inyLfxSllbxfhd3UAjL3n0ZOtTDjaI2AAkT7d3Exuddy8SQXvzxq7R8cR9C4yNuIJfMIeRRf-PGJRUujagenJ908KOdXYRuyMYYsVOQ4XZdK51wAHmYQcoQuf5Pc1ix9V0Sn-BGRfH7gJAHPQR8e9xIsdUGKtsfGsCqO7LFrU0h-G3nV8P50PhoVVdx0qm-g6XvAkasVJAGRUfu38TtBsrP6psZVu28iOwp6h-Xig3EJfRwnZQm3dcdPYjUXmZAwoZuppr0BvByGM77JWXo9WVlCKrgqS9Za3sZfYWe_jvVtglkVCT6kL6rLeA-00FL9p4jdEDtSmhPR2gX_6KStGc6_3W40j8y5ozhQfSsHHrH5D3tI5IxcXkVgGhWXbQ4hQRzqrX2p30PTkrRTl348AHP9Eb7AOApaNh96mmIk7WyGVltoyL2o9ICISW1y-dNYRqpVeOr5SCg7HsKZrehW77hW2Vrmj6-kEmGIjboST68WPkQISap0f88Zv25sOdamyAOAqK_nYx9XR6UEy5uUkDWbxlS8ddWAqL5JK8WTBZrNqurZKe4y5fAK2kIp_iy0i_34g-huNMCCgFhcuHfS2m5S6pzyvj6C2-zBdLjZ2OB9EnpEHTPYoErOS7lwhyrMKsFTeqGDB0ugtmvGV498ywzqTXv94F099w2_dM_4jz46uKO0gkb1hu_IuIoGJyR6SODmbWwNNEm00Af3pygfpJCUkCG3z1RU-TI8zOThFjnXoA205junYJPb26PrsFeTdY5iiEj3Dx-AQiDbj1CGfg3O9XJ9-PO8v6obP64SLRvIcrz4ExZHf-5zPTGQgAEKjzYXVrp7qEssciocNafcQreFEzD3r53EE59qs1Z7-j6z6SoGKNrJedAQGHl7REhlregaY|jAke98wA2tk3pCVhof1NROwtXq8; Path=/; SameSite=Lax; HttpOnly
set-cookie: 157c7d417676c54695fa6cf886b2feeb=eaee7aaac681437e37a61f18a4eccd92; path=/; HttpOnly
via: kong/2.8.1.2-enterprise-edition
x-kong-proxy-latency: 19
x-kong-upstream-latency: 2

Hello World, Magnanimo
```

## Clean up

Remove the `kuma-app` namespace containing the plugins, ingress, service and deployment for the `magnanimo` application.

Follow the [Gateway and Keycloak Clean up instructions](../gateway-plugins/README.md#clean-up)

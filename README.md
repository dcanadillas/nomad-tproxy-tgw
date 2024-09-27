# Nomad and Consul Service Mesh with TProxy and Terminating Gateways

## Requirements
* A Linux VM (example commands are Ubuntu/Debian based)
* Access to the Linux terminal of the VM

> NOTE: For ease of use you can use some virtualization platform like Multipass (Qemu based), VirtualBox or directly Qemu. For Windows use cases probably you could use WSL, but I didn't test it.

## Deploy your cluster

> NOTE: If you have already a Consul and Nomad cluster running you can skip this section. But bear in mind that you need at least Consul ACLs enabled to work with [Nomad Workload Identities](https://developer.hashicorp.com/nomad/docs/integrations/consul/acl#nomad-workload-identities)

> NOTE: You can also skip this if you use the [included Multipasss configuration installation](./multipass/README.md#deploy-consul-and-nomad-demo-with-multipass) 

Get into your Linux VM and Install required packages:
```bash
sudo apt install nomad consul uuid -y
```

Create required directories:
```bash
sudo mkdir /opt/consul
chown consul:consul /opt/consul
sudo mkdir /opt/nomad
chown nomad:nomad /opt/nomad
```

Clone the repo and get into it:
```bash
git clone https://github.com/dcanadillas/nomad-tproxy-tgw $HOME/nomad-tgw
cd $HOME/nomad-tgw
```

Save your configs in the right place from this repo:
```bash
sudo cp configs/consul.hcl /etc/consul.d/consul.hcl
sudo cp configs/nomad.hcl /etc/nomad.d/nomad.hcl
```
### Consul

Let's create a Bootstrap token for Consul and Nomad and save it (this is only for demo purposes):
```bash
uuid | sudo tee /etc/consul.d/.bootstrap_token
export CONSUL_HTTP_TOKEN=$(cat /etc/consul.d/.bootstrap_token)
```

Add the token in a config file to be bootstraped with Consul (for demo purposes we are using the bootstrap token as default):
```bash
cat - | tee -a /etc/consul.d/consul.hcl <<EOF

acl {
  enabled = true
  default_policy = "deny"
  tokens {
    initial_management = "$CONSUL_HTTP_TOKEN"
    default = "$CONSUL_HTTP_TOKEN"
    dns = "$CONSUL_HTTP_TOKEN"
  }
}

EOF
```

Let's create the certificates to be used with Consul:
```bash
consul tls ca create
consul tls cert create -server
```


Save them into the right place:
```bash
sudo mkdir -p /etc/consul.d/tls
sudo mv consul-agent-*.pem /etc/consul.d/tls/
sudo mv dc1-server-consul*.pem /etc/consul.d/tls/
```

And add the `tls` config for Consul:
```
cat - | sudo tee -a /etc/consul.d/consul.hcl <<EOF

tls {
  defaults {
    key_file = "/etc/consul.d/tls/dc1-server-consul-0-key.pem"
    cert_file = "/etc/consul.d/tls/dc1-server-consul-0.pem"
    ca_file = "/etc/consul.d/tls/consul-agent-ca.pem"
    # Following values will be false for demo purposes
    verify_incoming = false 
    verify_outgoing = false 
    verify_server_hostname = false 
  }
}

EOF
```

Export variables:
```
export CONSUL_HTTP_ADDR=https://$(ip route | grep ^default | awk ' {print $9}'):8501
export CONSUL_CACERT="/etc/consul.d/tls/consul-agent-ca.pem"
export CONSUL_TLS_SERVER_NAME="$(openssl x509 -in /etc/consul.d/tls/dc1-server-consul-0.pem  -subject | awk '/subject/ {print $NF}')"
```

### Nomad

> NOTE: In the case of Nomad we are not enabling ACLs (demo purposes), but for Consul we did to work with [Nomad Workload Identities](https://developer.hashicorp.com/nomad/docs/integrations/consul/acl#nomad-workload-identities).


Now that you have all Consul variables, add the Consul configuration into Nomad's. We will be also adding the Workload Identity config:
```bash
cat - | sudo tee -a /etc/nomad.d/nomad.hcl <<EOF

consul {
  token = "$CONSUL_HTTP_TOKEN"

  service_identity {
    aud = ["consul.io"]
    ttl = "1h"
  }

  task_identity {
    aud = ["consul.io"]
    ttl = "1h"
  }
}

EOF
```

```bash
export NOMAD_ADDR=http://$(ip route | grep ^default | awk ' {print $9}'):4646
```

### Consul CNI plugin
You must install Consul CNI plugin in order to use Transparent proxy:
```bash
sudo apt install consul-cni
```

### Run Consul and Nomad
Once that configuration is ready you need to run both Consul and Nomad:
```bash
sudo systemctl start consul
sudo systemctl start nomad
```

## Configure Workload Identity
Let's configure from Nomad the Consul auth method for Workload Identity:

```bash
nomad setup consul -jwks-url $NOMAD_ADDR/.well-known/jwks.json -y
```

## Deploy the demo applications
Deploy the two Nomad jobs included in the repo:
```bash
nomad run ./demo-fake-service/backend.nomad.hcl
```

```bash
nomad run ./demo-fake-service/frontend.nomad.hcl
```

Deploy the right intentions:
```bash
consul config write ./configs/private-api-intentions.hcl
```

```bash
consul config write ./configs/public-api-intentions.hcl
```

Check your application:
```bash
nomad exec -task web $(nomad operator api $NOMAD_ADDR/v1/job/front-service/allocations | jq -r '.[] | select(.ClientStatus == "running") | .ID') curl localhost:9090
```


## Configure the Terminating Gateway

Let's configure first the ACLs needed by the Terminating Gateways. For that, we will create a Consul policy associated with a Consul role, and then a binding rule for the auth method created by Nomad Workload Identity configuration. With this configuration, every time that we deploy a `terminating-gateway` service, the right policy should be attached.

Create first the policy. We included a policy in this repo to allow the Terminating Gateway to work with a demo example service called `tls-destination`:
```bash
consul acl policy create -name terminating-gateway \
-description "Policy for the Terminating Gateways" \
-rules @./configs/terminating-acl.hcl
```

Create the Consul role, associating the policy created:
```bash
consul acl role create -name terminating-gateway-role \
-description "A role for the TGW policies" \
-policy-name terminating-gateway
```

Add the binding rule:
```bash
consul acl binding-rule create \
-method nomad-workloads \
-bind-type role \
-bind-name terminating-gateway-role \
-selector 'value.nomad_service=="terminating-gateway"' 
```

Now it is time to deploy the Terminating Gateway:
```bash
nomad run ./tgw.nomad.hcl
```

You can look at the logs to check that the Terminating Gateway is working properly:
```bash
nomad alloc logs -stderr $(nomad operator api $NOMAD_ADDR/v1/job/terminating-gateway/allocations | jq -r '.[] | select(.ClientStatus == "running") | .ID')
```

## Configure Destinations
We will use [`ServiceDefaults` destinations](https://developer.hashicorp.com/consul/docs/connect/config-entries/service-defaults#destination) to service traffic through Terminating Gateway.

Deploy the `ServiceDefaults` with the file included:
```bash
consul config write ./configs/service-defaults-tls.hcl
```

And you also need to add the Consul intention to allow traffic from services to the `ServiceDefault` configured:
```bash
consul config write configs/tls-destination-intention.hcl
```

## Test Connectivity with MeshDestinationsOnly
To test that our traffic can be routed out of the mesh through Terminating Gateway using external addresses, we will force the traffic to go only trough the Mesh:
```bash
consul config write ./configs/mesh.hcl
```

And now we can check that only the addresses from the `ServiceDefaults` destinations (`developer.hashicorp.com` and `www.google.com`) can be reached thank to the Terminating Gateway configuration, who is routing the traffic in a passthrough way.

Here is the command with the output, executing a `curl` request from the `front-service` service, that is part of the service mesh:
```
$ nomad exec -task web $(nomad operator api $NOMAD_ADDR/v1/job/front-service/allocations | jq -r .[].ID) curl https://developer.hashicorp.com -IL
HTTP/2 200 
accept-ranges: bytes
access-control-allow-origin: *
age: 72580
cache-control: public, max-age=0, must-revalidate
content-disposition: inline
content-type: text/html; charset=utf-8
date: Fri, 20 Sep 2024 16:06:15 GMT
etag: "fe0bd32402b2c4757348e7c49bab17d7"
server: Vercel
set-cookie: hc_geo=country%3DES%2Cregion%3DMD; Path=/; Expires=Fri, 27 Sep 2024 16:06:15 GMT; Max-Age=604800
strict-transport-security: max-age=63072000
x-frame-options: SAMEORIGIN
x-matched-path: /
x-vercel-cache: HIT
x-vercel-id: cdg1::gfkw2-1726848375579-25349f3adffe
content-length: 87101
```

But you won't be able to reach any other external destination:
```
$ nomad exec -task web $(nomad operator api $NOMAD_ADDR/v1/job/front-service/allocations | jq -r .[].ID) curl https://amazon.com -IL
curl: (35) Recv failure: Connection reset by peer
```

So, if we try to reach to the other destinatio, it should be successful:
```
$ nomad exec -task web $(nomad operator api $NOMAD_ADDR/v1/job/front-service/allocations | jq -r .[].ID) curl https://www.google.com -I
HTTP/2 200 
content-type: text/html; charset=ISO-8859-1
content-security-policy-report-only: object-src 'none';base-uri 'self';script-src 'nonce-M3bRcCzaib1yMT6W1BgOPw' 'strict-dynamic' 'report-sample' 'unsafe-eval' 'unsafe-inline' https: http:;report-uri https://csp.withgoogle.com/csp/gws/other-hp
accept-ch: Sec-CH-Prefers-Color-Scheme
p3p: CP="This is not a P3P policy! See g.co/p3phelp for more info."
date: Fri, 20 Sep 2024 16:11:54 GMT
server: gws
x-xss-protection: 0
x-frame-options: SAMEORIGIN
expires: Fri, 20 Sep 2024 16:11:54 GMT
cache-control: private
set-cookie: AEC=AVYB7cr7UlpdoSK02hUImLUBD8e0jXZWjLTac6SqhMD96KKoDH4Fl-3S3mA; expires=Wed, 19-Mar-2025 16:11:54 GMT; path=/; domain=.google.com; Secure; HttpOnly; SameSite=lax
set-cookie: __Secure-ENID=22.SE=BvNsO4mgFxTxhV0TtnMM9F8zaEqh2u3bbfqfLTvsxip6YrwjRMAck62vuALdH7FtOwhgcpxUaJEBEXJDNur1mMIHDeDLWjkSLrVKdMi1Hq85PUIb2fNEbPOa1gSIXGQdNqfRvVL6QW1S4XwB4-PjSsRB6CK7j4GnHmJxu0gX3RIs4dZbR-TXKSUifNO1oB703yMJEp_TRaDisroh9U5a-mijtHitrz34IXN_yOU; expires=Tue, 21-Oct-2025 08:30:12 GMT; path=/; domain=.google.com; Secure; HttpOnly; SameSite=lax
```

## Deploy the API Gateway

**THIS SECTION IS STILL UNDER DEVELOPMENT**

Nomad namespace for the gateway:
```bash
nomad namespace apply \
    -description "namespace for Consul API Gateways" \
    ingress
```

Binding rule to apply automatically the right policy:
```bash
consul acl binding-rule create \
    -method 'nomad-workloads' \
    -description 'Nomad API gateway' \
    -bind-type 'templated-policy' \
    -bind-name 'builtin/api-gateway' \
    -bind-vars 'Name=${value.nomad_job_id}' \
    -selector '"nomad_service" not in value and value.nomad_namespace==ingress'
```

...
...
...

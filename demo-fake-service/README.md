# Nomad and Consul Service Mesh with TProxy and Terminating Gateways

## Requirements
* A Linux VM (example commands are Ubuntu/Debian based)
* Access to the Linux terminal of the VM

> NOTE: For ease of use you can use some virtualization platform like Multipass (Qemu based), VirtualBox or directly Qemu. For Windows use cases probably you could use WSL, but I didn't test it.

## Deploy your cluster

> NOTE: If you have already a Consul and Nomad cluster running you can skip this section. But bear in mind that you need at least Consul ACLs enabled to work with [Nomad Workload Identities](https://developer.hashicorp.com/nomad/docs/integrations/consul/acl#nomad-workload-identities)

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
git clone <this_repo_url> $HOME/nomad-tgw
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
export CONSUL_CACERT="/etc/consul.d/tls/consul-agent-ca.pem
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
nomad exec -task web $(nomad operator api $NOMAD_ADDR/v1/job/front-service/allocations | jq -r .[].ID) sh 
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

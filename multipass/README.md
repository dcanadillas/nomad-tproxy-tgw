# Deploy Consul and Nomad demo with Multipass

[There is a `cloud-init` script](./cloud-init.yaml) to deploy Nomad and Consul ready in a Multipass VM.

## Requirements

* [Canonical Multipass installed](https://multipass.run/install) in your machine
* 4core+ machine with 8GB+ memory (probably less resources could be used but it wasn't tested)

## Deploy the cluster

You just only need to execute from a terminal the following command (from the root directory of the repo):
```bash
multipass launch -n nomad-consul -c 4 -m 4GB -d 20G --cloud-init ./multipass/cloud-init.yaml
```

Once the vm is created check that it is running. Here is the example command with the output:
```
david ➜ ~ $ multipass list
Name                    State             IPv4             Image
nomad-consul            Running           192.168.105.22   Ubuntu 24.04 LTS
                                          172.17.0.1
                                          172.26.64.1
                                          10.1.221.0
```
## Start your services
You can start Consul and Nomad directly from the terminal:
```bash
multipass exec nomad-consul systemctl start consul
```

```bash
multipass exec nomad-consul systemctl start nomad
```

And get into the VM with:
```bash
multipass shell nomad-consul
```

After Consul and Nomad are running you can continue with configurations [here](../README.md#configure-workload-identity).


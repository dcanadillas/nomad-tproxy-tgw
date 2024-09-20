data_dir  = "/opt/nomad"
bind_addr = "0.0.0.0"

server {
  #license_path = "/etc/nomad.d/license.hclic"
  enabled          = true
  bootstrap_expect = 1
}

client {
  enabled = true
  servers = ["127.0.0.1"]
  cpu_total_compute = 4000
}
consul {
  token = "ConsulR0cks"
}

plugin "docker" {
  config {
    allow_privileged = true
    volumes {
      enabled = true
    }
  }
}
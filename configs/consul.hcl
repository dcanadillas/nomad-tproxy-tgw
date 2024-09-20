datacenter = "dc1"
data_dir = "/opt/consul"
client_addr = "0.0.0.0"
log_level = "INFO"
ui_config{
  enabled = true
}

auto_encrypt {
  allow_tls = true
}

recursors = ["8.8.8.8","1.1.1.1"]

ports {
  https = 8501
  grpc = 8502
  grpc_tls = 8503
  dns = 8600
}

server = true

#bind_addr = "[::]" # Listen on all IPv6
bind_addr = "{{ GetDefaultInterfaces | attr \"address\" }}"
# advertise_addr = "{{ GetInterfaceIP \"enp0s1\" }}"

#license_path = "/etc/consul.d/consul.hclic"

bootstrap_expect=1
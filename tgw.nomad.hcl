variable "datacenter" {
  default = "dc1"
}
job "terminating-gateway" {

  datacenters = ["${var.datacenter}"]
  group "gateway" {
    network {
      mode = "bridge"
    }

    service {
      name = "terminating-gateway"

      connect {
        gateway {
          proxy {
          }

          terminating {
            service {
              name = "tls-destination"
            }
          }
        }
      }
    }
  }
}

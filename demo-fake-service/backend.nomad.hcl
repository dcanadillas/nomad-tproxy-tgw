variable "back_version" {
  type = string
  default = "v0.26.2"
}

job "backend-services" {

  group "public" {
    network {
      mode = "bridge"
      port "public-api" {
        to = 9090
      }
    }
    service {
      name = "public-api"
      tags = ["api","public"]
      port = "public-api"
      # For TProxy and Consul Connect we need to use the port and address of the Allocation when using port names
      address_mode = "alloc"

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {}
          } 
        }
      }
    }

    task "public-api" {
      driver = "docker"

      config {
        image          = "nicholasjackson/fake-service:${var.back_version}"
      }

      env {
        PORT = "${NOMAD_PORT_public-api}"
        LISTEN_ADDR = "0.0.0.0:9090"
        MESSAGE = "Hello World from Public API"
        NAME = "Public API"
      }
    }
  }
  group "private" {
    network {
      mode = "bridge"
      port "private-api" {
        to = 9090
      }
    }
    service {
      name = "private-api"
      tags = ["api","private"]
      port = "private-api"
      # For TProxy and Consul Connect we need to use the port and address of the Allocation when using port names
      address_mode = "alloc"

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {}
          } 
        }
      }
    }

    task "private-api" {
      driver = "docker"

    
      config {
        image          = "nicholasjackson/fake-service:${var.back_version}"
        ports          = ["private-api"]
      }

      # identity {
      #   env  = true
      #   file = true
      # }

      env {
        PORT = "9090"
        LISTEN_ADDR = "0.0.0.0:9090"
        MESSAGE = "Hello World from Private API"
        NAME = "Private API"
      }
    }
  }
}

Kind = "service-defaults"
Name = "tls-destination"
Protocol = "tcp"
Destination {
  Addresses = ["developer.hashicorp.com","www.google.com"]
  Port = 443
}
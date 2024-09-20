Kind = "service-intentions"
Name = "tls-destination"
Sources = [
  {
    Name   = "front-service"
    Action = "allow"
  },
  {
    Name   = "public-api"
    Action = "allow"
  },
  {
    Name   = "private-api"
    Action = "allow"
  }
]

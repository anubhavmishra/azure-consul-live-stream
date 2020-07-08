Kind = "service-resolver"
Name = "api"

Failover = {
  "*" = {
    datacenters = ["us-west-1"]
  }
}

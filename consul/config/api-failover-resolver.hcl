kind = "service-resolver"
name = "api"

failover = {
  "*" = {
    datacenters = ["us-west-1"]
  }
}

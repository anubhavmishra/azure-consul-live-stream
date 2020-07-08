Kind = "service-resolver"
Name = "api"

DefaultSubset = "v1"

Subsets = {
  "v1" = {
    Filter = "Service.Meta.version == 1"
  }
  "v2" = {
    Filter = "Service.Meta.version == 2"
  }
}
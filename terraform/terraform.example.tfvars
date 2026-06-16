host_project_id     = "YOUR_HOST_PROJECT_ID"
service_project_id  = "YOUR_SERVICE_PROJECT_ID"
service_project_num = "YOUR_SERVICE_PROJECT_NUMBER"
region              = "europe-west2"

# Firewall mode:
#   enforce  = default deny blocks unmatched traffic (default)
#   audit    = all traffic allowed, logging enabled so you can see what
#              would be blocked before switching to enforce
# firewall_mode = "enforce"

# Optional: source allow lists from an external repo (e.g. git submodule).
# null  = use the built-in allowed-hosts.txt / allowed-cidrs.txt in this repo
# /abs  = absolute path to a directory containing the files
# rel   = path relative to the terraform/ directory
# allowlist_dir = "external-allowlists"

# Optional: override allow lists entirely (all entries get * / all ports).
# When set, takes precedence over both local and external files.
# allowed_fqdns = ["google.com", "github.com"]
# allowed_cidrs = ["10.0.0.0/8"]

############################################
# Define Providers in this section  
############################################
provider "google" {
  project     = "my-project-id"
  region      = "us-central1"
}


##################### Deploy Frontend Service along with HTTPS External Loadbalancer#########################################

data "google_compute_default_service_account" "default" {
}

data "google_compute_image" "my_image" {
  family  = "debian-11"
  project = "debian-cloud"
}

# VPC
resource "google_compute_network" "default" {
  name                    = "l7-xlb-network"
  provider                = google-beta
  auto_create_subnetworks = false
}

# backend subnet
resource "google_compute_subnetwork" "default" {
  name          = "l7-xlb-subnet"
  provider      = google-beta
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.default.id
}

# reserved IP address
resource "google_compute_global_address" "default" {
  provider = google-beta
  name     = "l7-xlb-static-ip"
}

# forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "l7-xlb-forwarding-rule"
  provider              = google-beta
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}

# http proxy
resource "google_compute_target_http_proxy" "default" {
  name     = "l7-xlb-target-http-proxy"
  provider = google-beta
  url_map  = google_compute_url_map.default.id
}

# url map
resource "google_compute_url_map" "default" {
  name            = "l7-xlb-url-map"
  provider        = google-beta
  default_service = google_compute_backend_service.default.id
}

# backend service with custom request and response headers
resource "google_compute_backend_service" "default" {
  name                    = "l7-xlb-backend-service"
  provider                = google-beta
  protocol                = "HTTP"
  port_name               = "my-port"
  load_balancing_scheme   = "EXTERNAL"
  timeout_sec             = 10
  enable_cdn              = true
  custom_request_headers  = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  custom_response_headers = ["X-Cache-Hit: {cdn_cache_status}"]
  health_checks           = [google_compute_health_check.default.id]
  backend {
    group           = google_compute_instance_group_manager.default.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# instance template
resource "google_compute_instance_template" "default" {
  name         = "l7-xlb-mig-template"
  provider     = google-beta
  machine_type = "e2-small"
  tags         = ["allow-health-check"]

  network_interface {
    network    = google_compute_network.default.id
    subnetwork = google_compute_subnetwork.default.id
    access_config {
      # add external ip to fetch packages
    }
  }
  disk {
    source_image = "debian-cloud/debian-10"
    auto_delete  = true
    boot         = true
  }

  # install nginx and serve a simple web page
  metadata = {
    startup-script = <<-EOF1
      #! /bin/bash
      set -euo pipefail

      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y nginx-light jq

      NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/hostname")
      IP=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip")
      METADATA=$(curl -f -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/?recursive=True" | jq 'del(.["startup-script"])')

      cat <<EOF > /var/www/html/index.html
      <pre>
      Name: $NAME
      IP: $IP
      Metadata: $METADATA
      </pre>
      EOF
    EOF1
  }
  lifecycle {
    create_before_destroy = true
  }
}

# health check
resource "google_compute_health_check" "default" {
  name     = "l7-xlb-hc"
  provider = google-beta
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

# MIG
resource "google_compute_instance_group_manager" "default" {
  name     = "l7-xlb-mig1"
  provider = google-beta
  zone     = "us-central1-c"
  named_port {
    name = "http"
    port = 8080
  }
  version {
    instance_template = google_compute_instance_template.default.id
    name              = "primary"
  }
  base_instance_name = "vm"
  target_size        = 2
}

# allow access from health check ranges
resource "google_compute_firewall" "default" {
  name          = "l7-xlb-fw-allow-hc"
  provider      = google-beta
  direction     = "INGRESS"
  network       = google_compute_network.default.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  allow {
    protocol = "tcp"
  }
  target_tags = ["allow-health-check"]
}



##################################### Create Middle layer with Internal Load Balancer #########################


# VPC network
resource "google_compute_network" "default" {
  name                    = "l7-ilb-network"
  auto_create_subnetworks = false
}

# Proxy-only subnet
resource "google_compute_subnetwork" "proxy_subnet" {
  name          = "l7-ilb-proxy-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "europe-west1"
  purpose       = "INTERNAL_HTTPS_LOAD_BALANCER"
  role          = "ACTIVE"
  network       = google_compute_network.default.id
}

# Backend subnet
resource "google_compute_subnetwork" "default" {
  name          = "l7-ilb-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "europe-west1"
  network       = google_compute_network.default.id
}

# Reserved internal address
resource "google_compute_address" "default" {
  name         = "l7-ilb-ip"
  provider     = google-beta
  subnetwork   = google_compute_subnetwork.default.id
  address_type = "INTERNAL"
  address      = "10.0.1.5"
  region       = "europe-west1"
  purpose      = "SHARED_LOADBALANCER_VIP"
}

# Regional forwarding rule
resource "google_compute_forwarding_rule" "default" {
  name                  = "l7-ilb-forwarding-rule"
  region                = "europe-west1"
  depends_on            = [google_compute_subnetwork.proxy_subnet]
  ip_protocol           = "TCP"
  ip_address            = google_compute_address.default.id
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_region_target_https_proxy.default.id
  network               = google_compute_network.default.id
  subnetwork            = google_compute_subnetwork.default.id
  network_tier          = "PREMIUM"
}

# Self-signed regional SSL certificate for testing
resource "tls_private_key" "default" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "default" {
  private_key_pem = tls_private_key.default.private_key_pem

  # Certificate expires after 12 hours.
  validity_period_hours = 12

  # Generate a new certificate if Terraform is run within three
  # hours of the certificate's expiration time.
  early_renewal_hours = 3

  # Reasonable set of uses for a server SSL certificate.
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = ["example.com"]

  subject {
    common_name  = "example.com"
    organization = "ACME Examples, Inc"
  }
}

resource "google_compute_region_ssl_certificate" "default" {
  name_prefix = "my-certificate-"
  private_key = tls_private_key.default.private_key_pem
  certificate = tls_self_signed_cert.default.cert_pem
  region      = "europe-west1"
  lifecycle {
    create_before_destroy = true
  }
}

# Regional target HTTPS proxy
resource "google_compute_region_target_https_proxy" "default" {
  name             = "l7-ilb-target-https-proxy"
  region           = "europe-west1"
  url_map          = google_compute_region_url_map.https_lb.id
  ssl_certificates = [google_compute_region_ssl_certificate.default.self_link]
}

# Regional URL map
resource "google_compute_region_url_map" "https_lb" {
  name            = "l7-ilb-regional-url-map"
  region          = "europe-west1"
  default_service = google_compute_region_backend_service.default.id
}

# Regional backend service
resource "google_compute_region_backend_service" "default" {
  name                  = "l7-ilb-backend-service"
  region                = "europe-west1"
  protocol              = "HTTP"
  port_name             = "http-server"
  load_balancing_scheme = "INTERNAL_MANAGED"
  timeout_sec           = 10
  health_checks         = [google_compute_region_health_check.default.id]
  backend {
    group           = google_compute_region_instance_group_manager.default.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# Instance template
resource "google_compute_instance_template" "default" {
  name         = "l7-ilb-mig-template"
  machine_type = "e2-small"
  tags         = ["http-server"]
  network_interface {
    network    = google_compute_network.default.id
    subnetwork = google_compute_subnetwork.default.id
    access_config {
      # add external ip to fetch packages
    }
  }
  disk {
    source_image = "debian-cloud/debian-10"
    auto_delete  = true
    boot         = true
  }

  # install nginx and serve a simple web page
  metadata = {
    startup-script = <<-EOF1
      #! /bin/bash
      set -euo pipefail

      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y nginx-light jq

      NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/hostname")
      IP=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip")
      METADATA=$(curl -f -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/?recursive=True" | jq 'del(.["startup-script"])')

      cat <<EOF > /var/www/html/index.html
      <pre>
      Name: $NAME
      IP: $IP
      Metadata: $METADATA
      </pre>
      EOF
    EOF1
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Regional health check
resource "google_compute_region_health_check" "default" {
  name   = "l7-ilb-hc"
  region = "europe-west1"
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

# Regional MIG
resource "google_compute_region_instance_group_manager" "default" {
  name   = "l7-ilb-mig1"
  region = "europe-west1"
  version {
    instance_template = google_compute_instance_template.default.id
    name              = "primary"
  }
  named_port {
    name = "http-server"
    port = 80
  }
  base_instance_name = "vm"
  target_size        = 2
}

# Allow all access to health check ranges
resource "google_compute_firewall" "default" {
  name          = "l7-ilb-fw-allow-hc"
  direction     = "INGRESS"
  network       = google_compute_network.default.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "35.235.240.0/20"]
  allow {
    protocol = "tcp"
  }
}

# Allow http from proxy subnet to backends
resource "google_compute_firewall" "backends" {
  name          = "l7-ilb-fw-allow-ilb-to-backends"
  direction     = "INGRESS"
  network       = google_compute_network.default.id
  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["http-server"]
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
}

# Test instance
resource "google_compute_instance" "default" {
  name         = "l7-ilb-test-vm"
  zone         = "europe-west1-b"
  machine_type = "e2-small"
  network_interface {
    network    = google_compute_network.default.id
    subnetwork = google_compute_subnetwork.default.id
  }
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
}

### HTTP-to-HTTPS redirect ###

# Regional forwarding rule
resource "google_compute_forwarding_rule" "redirect" {
  name                  = "l7-ilb-redirect"
  region                = "europe-west1"
  ip_protocol           = "TCP"
  ip_address            = google_compute_address.default.id # Same as HTTPS load balancer
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.default.id
  network               = google_compute_network.default.id
  subnetwork            = google_compute_subnetwork.default.id
  network_tier          = "PREMIUM"
}

# Regional HTTP proxy
resource "google_compute_region_target_http_proxy" "default" {
  name    = "l7-ilb-target-http-proxy"
  region  = "europe-west1"
  url_map = google_compute_region_url_map.redirect.id
}

# Regional URL map
resource "google_compute_region_url_map" "redirect" {
  name            = "l7-ilb-redirect-url-map"
  region          = "europe-west1"
  default_service = google_compute_region_backend_service.default.id
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_region_backend_service.default.id
    path_rule {
      paths = ["/"]
      url_redirect {
        https_redirect         = true
        host_redirect          = "10.0.1.5:443"
        redirect_response_code = "PERMANENT_REDIRECT"
        strip_query            = true
      }
    }
  }
}



############################## Cloud SQL Database Instance ########################################

resource "google_sql_database_instance" "postgres" {
  name             = "postgres-instance-${random_id.db_name_suffix.hex}"
  database_version = "POSTGRES_14"

  settings {
    tier = "db-f1-micro"

    ip_configuration {

      dynamic "authorized_networks" {
        for_each = google_compute_instance.apps
        iterator = apps

        content {
          name  = apps.value.name
          value = apps.value.network_interface.0.access_config.0.nat_ip
        }
      }

      dynamic "authorized_networks" {
        for_each = local.onprem
        iterator = onprem

        content {
          name  = "onprem-${onprem.key}"
          value = onprem.value
        }
      }
    }
  }
}


resource "google_sql_database" "database" {
  name     = "my-database"
  instance = google_sql_database_instance.instance.name
}


resource "google_sql_user" "users" {
  name     = "me@example.com"
  instance = google_sql_database_instance.main.name
  type     = "CLOUD_IAM_USER"
}


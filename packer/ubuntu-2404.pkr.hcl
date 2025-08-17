packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region"  { default = "eu-central-1" }
variable "ami_name" { default = "linux-troubleshooting-lab-v1" }
variable "artifact_version" { default = "v1" }

source "amazon-ebs" "ubuntu" {
  region                  = var.region
  instance_type           = "t3.small"
  ssh_username            = "ubuntu"
  ami_name                = var.ami_name
  ami_description         = "Linux Troubleshooting Lab v1"
  force_deregister        = true
  force_delete_snapshot   = true
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture        = "x86_64"
    }
    owners      = ["099720109477"]   # Canonical
    most_recent = true
  }
  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 20
    volume_type = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "ubuntu-2404-lab"
  sources = ["source.amazon-ebs.ubuntu"]

  # copy salt states
  provisioner "file" {
    source      = "../salt"
    destination = "/tmp/salt"
  }

  # copy locally built artifacts
  provisioner "file" {
    source      = "../artifacts/v1"
    destination = "/tmp/artifacts"
  }

  provisioner "shell" {
    script = "scripts/install-salt.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo salt-call --local state.apply -l debug",
      #      "sudo salt-call --local state.apply roles.php -l debug",
      #"sudo salt-call --local state.apply roles.challenges -l debug",
      #"sudo salt-call --local state.apply roles.dashboard -l debug",
      #"sudo salt-call --local state.apply roles.endpoints -l debug"
    ]
  }

  provisioner "shell" {
    script = "scripts/cleanup-build.sh"
  }

  post-processors {
    post-processor "manifest" {
      # path is relative to the working dir where you run `packer build`
      output = "manifest.json"
      # optional but handy metadata for later parsing:
      custom_data = {
        region            = var.region
        artifact_version  = var.artifact_version
        ami_name          = var.ami_name
      }
    }
  }
}


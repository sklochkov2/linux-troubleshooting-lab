variable "region" { default = "eu-west-2" }
variable "ami_id" { description = "AMI built by Packer" }
variable "instance_type" { default = "t3.micro" }
variable "key_name" { description = "EC2 key pair name" }
variable "ssh_cidr" { default = "0.0.0.0/0" } # lock down as needed

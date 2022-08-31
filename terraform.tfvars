region               = "us-east-2"
bucket_name          = "gl-yunyuy-test"
environment          = "dev"
vpc_cidr             = "10.0.0.0/16"
public_subnets_cidr  = ["10.0.0.0/24", "10.0.2.0/24"]
private_subnets_cidr = ["10.0.1.0/24", "10.0.3.0/24"]
availability_zones   = ["us-east-2a", "us-east-2b"]
db_password          = "gitlab123"
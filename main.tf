locals {
  gitlab_assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com",
          "ecs-tasks.amazonaws.com",
          "events.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

}

# Create S3 Bucket
resource "aws_s3_bucket" "s3_gitlab" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_acl" "gitlab_bucket_acl" {
  bucket = aws_s3_bucket.s3_gitlab.id
  acl    = var.acl_value
}


# Create IAM Roles

resource "aws_iam_role" "gitlab_runtime" {
  name               = "gitlab-runtime"
  assume_role_policy = local.gitlab_assume_role_policy
}

resource "aws_iam_policy" "gitlab" {
  name        = "gitlab-runtime"
  description = "runtime access policy for all services"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:CopyObject",
        "s3:GetObject",
        "s3:PutObject",
        "s3:GetObjectAcl",
        "s3:PutObjectAcl",
        "s3:DeleteObject"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::gl-*/*"
      ]
    },
    {
      "Action": [
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"

      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::gl-*/*"
      ]
    },
    {
      "Action": [
        "ssm:GetParameters",
        "ecr:UploadLayerPart",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:GetAuthorizationToken",
        "ecr:CompleteLayerUpload",
        "ecr:BatchCheckLayerAvailability",
        "ec2:CreateNetworkInterface",
        "ec2:CreateNetworkInterfacePermission",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.gitlab_runtime.name
  policy_arn = aws_iam_policy.gitlab.arn
}

/*==== The VPC ======*/
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "gitlab-vpc"
    Environment = "${var.environment}"
  }
}
/*==== Subnets ======*/
/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "${var.environment}-igw"
    Environment = "${var.environment}"
  }
}
/* Elastic IP for NAT */
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
}
/* NAT */
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
  depends_on    = [aws_internet_gateway.ig]
  tags = {
    Name        = "nat"
    Environment = "${var.environment}"
  }
}
/* Public subnet */
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-      public-subnet"
    Environment = "${var.environment}"
  }
}
/* Private subnet */
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-private-subnet"
    Environment = "${var.environment}"
  }
}
/* Routing table for private subnet */
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "${var.environment}-private-route-table"
    Environment = "${var.environment}"
  }
}
/* Routing table for public subnet */
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "${var.environment}-public-route-table"
    Environment = "${var.environment}"
  }
}
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}
resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}
/* Route table associations */
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private.id
}
/*==== VPC's Default Security Group ======*/
resource "aws_security_group" "default" {
  name        = "${var.environment}-default-sg"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.vpc.id
  depends_on  = [aws_vpc.vpc]
  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = "true"
  }
  tags = {
    Environment = "${var.environment}"
  }
}

#HTTP
resource "aws_security_group" "http" {
  name       = "${var.environment}-http-sg"
  vpc_id     = aws_vpc.vpc.id
  depends_on = [aws_vpc.vpc]
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Environment = "${var.environment}"
  }
}

#HTTPS
resource "aws_security_group" "https" {
  name       = "${var.environment}-https-sg"
  vpc_id     = aws_vpc.vpc.id
  depends_on = [aws_vpc.vpc]
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Environment = "${var.environment}"
  }
}

#Postgre SG
resource "aws_security_group" "postgres" {
  name        = "allow-postgresql-traffic"
  description = "A security group that allows inbound access to a PostgreSQL DB instance."
  vpc_id      = aws_vpc.vpc.id
  depends_on  = [aws_vpc.vpc]

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow connections to a PostgreSQL DB instance"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

#Redis SG

resource "aws_security_group" "redis" {
  name        = "allow-redis-traffic"
  description = "A security group that allows inbound access to a Redis instance."
  vpc_id      = aws_vpc.vpc.id
  depends_on  = [aws_vpc.vpc]

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow connections to a Redis instance"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

# Create a new load balancer
resource "aws_elb" "terra-elb" {
  name            = "gl-elb"
  subnets         = aws_subnet.public_subnet.*.id
  security_groups = [aws_security_group.http.id, aws_security_group.https.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  #listener {
  #  instance_port      = 80
  #  instance_protocol  = "http"
  #  lb_port            = 443
  #  lb_protocol        = "https"
  #  ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/certName"
  #}

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/index.html"
    interval            = 30
  }

  #instances                   = []
  cross_zone_load_balancing   = true
  idle_timeout                = 100
  connection_draining         = true
  connection_draining_timeout = 300

  tags = {
    Name = "terraform-elb"
  }
}



/*==== RDS Postgres ======*/

#Subnet Group
resource "aws_db_subnet_group" "gitlab" {
  name       = "gitlab-sg"
  subnet_ids = aws_subnet.public_subnet.*.id

  tags = {
    Name = "gitlab"
  }
}

#Parameter Group

resource "aws_db_parameter_group" "gitlab" {
  name   = "gitlab"
  family = "postgres11"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

#DB
resource "aws_db_instance" "gitlab_instance" {
  identifier             = "gitlab"
  instance_class         = "db.t3.micro"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "11.14"
  username               = "gitlab"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.gitlab.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  parameter_group_name   = aws_db_parameter_group.gitlab.name
  publicly_accessible    = true
  skip_final_snapshot    = true
}

/*==== Elasticache Redis ======*/


resource "aws_elasticache_subnet_group" "gitlab" {
  name       = "gitlab-redis-subnet"
  subnet_ids = aws_subnet.public_subnet.*.id
}

resource "aws_elasticache_security_group" "gitlab" {
  name                 = "elasticache-security-group"
  security_group_names = [aws_security_group.redis.name, aws_security_group.default.name]
}

resource "aws_elasticache_cluster" "gitlab" {
  cluster_id           = "gitlab"
  engine               = "redis"
  node_type            = "cache.m4.large"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  engine_version       = "3.2.10"
  port                 = 6379
  #  security_group_names = [aws_elasticache_security_group.gitlab.name]
  #  security_group_ids   = [aws_security_group.redis.id, aws_security_group.default.id]
  subnet_group_name = aws_elasticache_subnet_group.gitlab.name

}
# set service provider type, in this case: amazon
provider "aws" {
  region = "eu-west-1"
}

# add db provider
provider "postgresql" {
        host = aws_db_instance.br-test-strict.address
        port = aws_db_instance.br-test-strict.port
        username = "mradmin"
        password = var.db_pwd
        sslmode = "require"

        superuser = false

        expected_version = "12.3"
}

# Ubuntu 20.04, eu-west-1, free-tier: ami-0127d62154efde733
# launch configuration group to be used by autoscaling group later
resource "aws_launch_configuration" "br-test-strict" {
    image_id = var.ami_ubuntu2004
    instance_type = "t2.micro"
    security_groups = [aws_security_group.instance.id]
   
    user_data = data.template_file.entrypoint.rendered
}

# define autoscaling group using launch configuration defined earlier
resource "aws_autoscaling_group" "br-test-strict" {
    launch_configuration = aws_launch_configuration.br-test-strict.name
    vpc_zone_identifier = data.aws_subnet_ids.default.ids
    
    health_check_type = "ELB"

    min_size = 1
    max_size = 1

    tag {
        key = "Name"
        value = "terraform-asg-br-test-strict"
        propagate_at_launch = true
    }
}

# define database instance
resource "aws_db_instance" "br-test-strict" {
    identifier_prefix = "test-db"
    engine = "postgres"
    engine_version = "12.3"
    allocated_storage = 5
    instance_class = "db.t2.micro"
    name = "br_date_db"
    username = "mradmin"

    publicly_accessible = true
    vpc_security_group_ids = [aws_security_group.br_date_db.id]

    skip_final_snapshot = true

    password = var.db_pwd
}

# create database admin role
resource "postgresql_role" "dbmanager" {
    name = "dbmanager"
    login = true
    password = var.db_manager_pwd
    create_database = true
}

# create database user role
resource "postgresql_role" "dbuser" {
    name = "dbuser"
    login = true
    password = var.db_user_pwd
}

resource "postgresql_schema" "br_date_db_schema" {
    name = "br_date_db_schema"
    database = aws_db_instance.br-test-strict.name

    policy {
        create = true
        usage = true
        role = postgresql_role.dbmanager.name
    }

    policy {
        usage = true
        role = postgresql_role.dbuser.name
    }
}

# EC2 security group for instance
resource "aws_security_group" "instance" {
    name = "terraform-br-test-strict-sec-group"

    ingress {
        from_port = var.http_port
        to_port = var.http_port
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# security group for db instance
resource "aws_security_group" "br_date_db" {
    name = "terraform-br-test-db-strict-sec-group"

    ingress {
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}
# collect from AWS acc and define default VPC available in AWS account to be
# used in ASG as data source; my default subnet in VPC is 172.31.0.0/16
data "aws_vpc" "default" {
    default = true
}

# subnets as data source using previously defined default aws_vpc
data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}

# define user data script
data "template_file" "entrypoint" {
    template = file("entrypoint.sh")
    
    vars = {
        http_port = var.http_port
        db_address = aws_db_instance.br-test-strict.address
        db_port = aws_db_instance.br-test-strict.port

        dbname = aws_db_instance.br-test-strict.name

        dbadmin = aws_db_instance.br-test-strict.username
        db_admin_pwd = var.db_pwd

        dbmanager = postgresql_role.dbmanager.name
        db_manager_pwd = var.db_manager_pwd

        dbuser = postgresql_role.dbuser.name
        db_user_pwd = var.db_user_pwd

        db_table = var.db_table
        db_schema = postgresql_schema.br_date_db_schema.name
    }
}

# data source to collect public ipv4 of an instance
data "aws_instances" "nodes" {
    depends_on = [aws_autoscaling_group.br-test-strict]

    filter {
        name = "tag:Name"
        values = ["terraform-asg-br-test-strict"]
    }
}

# define ami id
variable "ami_ubuntu2004" {
    description = "This is a Ubuntu 20.04 AMI"
    type = string
    default = "ami-0127d62154efde733"
}

# define default http port (80/tcp)
variable "http_port" {
    description = "This is a default port used for http server"
    type = number
    default = 80
}

# define http protocol
variable "http_proto" {
    description = "This is a http protocol"
        type = string
        default = "HTTP"
}

# master db pwd var
variable "db_pwd" {
    description = "The password for database"
    type = string
}

# user to create and manage db
variable "db_manager_pwd" {
    description = "Role to create and manage database"
    type = string
}

# user to access database
variable "db_user_pwd" {
    description = "Role to access database"
    type = string
}

# table to create
variable "db_table" {
    description = "This table will be created"
    type = string
    default = "br_date"
}

# output for public ipv4 of an instance
output "node_public_ipv4" {
    value = data.aws_instances.nodes.public_ips
}

# output for entry point of an rds postgresql instance
output "rds_pgsql_public_dns" {
    value = aws_db_instance.br-test-strict.address
}

# test task infrastructure, July 24, 2020
# Ilya Moiseev <ilya@moiseev>

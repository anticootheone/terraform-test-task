## Test task to create AWS infrastructure

#### This package consist of:
* `main.tf` -- Terraform configuration file for infrastructure
* `entrypoint.sh` -- User data script to prepare database and insert date into it
* `task.sh` -- Script-wrapper to make some checks and create infrastructure automatically.

#### Usage
Run `task.sh` script with correct options and it will create infrastructure automatically, without user interaction.

Example usage, in case of not having preconfigured AWS IAM user credentials in global environmental variables: 
* To create infrastructure: `task.sh -i "AWS Key ID value" -s "AWS Secret Key"`
* To destroy created infrastructure: `task.sh -i "AWS Key ID value" -s "AWS Secret Key" -d "yes"`

For detailed help run `task.sh -h`.

#### Purpose
Test task to create infrastructure in AWS using Terraform

#### Author
Ilya Moiseev <ilya@moiseev.su>

#### Credits
This piece of code uses third-party tool: [Terraform](https://www.terraform.io/)

License: [https://github.com/hashicorp/terraform/blob/master/LICENSE](https://github.com/hashicorp/terraform/blob/master/LICENSE)


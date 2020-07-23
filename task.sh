#!/usr/bin/env bash

# Author: Ilya Moiseev <ilya@moiseev.su>
# Purpose: Test task for DevOps engineer position
# License: MIT
# Date: July, 24 2020
#

# TODO: - use STDERR for exit 1

# Print help
function print_usage() {
    local usage="
$0 -- create or destroy created infrastructure in AWS for testing purpose.

$0 [ -i \"AWS Key ID value\" ] [ -s \"AWS Secret Key\" ] | [ -d \"yes\" ] | [ -h ]

    -i \"AWS Key ID value\" -- Set AWS_ACCESS_KEY_ID enviromental variable. If 
                             not set $0 will check for global variable 
                             in the current shell.
          
    -s \"AWS Secret Key\"   -- Set AWS_SECRET_ACCESS_KEY enviromental variable. 
                             If not set $0 will check for global variable 
                             in the current shell.

    -d \"yes\" -- Destroy created infrastructure.  

    -h -- Show this help.

Examples:
    $0
        Running script without arguments will attempt to create required 
        infrastructure in AWS using pre-set AWS credentials.

    $0 -i \"AWS Key ID value\" -s \"AWS Secret Key\"
        Running script with this settings will use specified AWS Key ID  and 
        AWS Secret Key as AWS credentials, and then it will attempt to create
        infrastructure.

    $0 -d "yes"
        Running script with this setting will attepmt to destroy created AWS
        infrastructure described in terraform infrastructure configuration file 
        and local tfstate file using credentials from global enviroment.
        
    $0 -i \"AWS Key ID value\" -s \"AWS Secret Key\" -d "yes"
        Running script with this setting will attepmt to destroy created AWS
        infrastructure described in terraform infrastructure configuration file 
        and local tfstate file using credentials set by operator.
        "

    printf "$usage\n"
    exit 0
}

# Local logger
function mylogger() {
    local text_to_print=$1
    printf "$(date '+%m/%d/%Y %H:%M:%S') : Info  : %s \n" "$text_to_print" | tee -a "$log_file"
}

# Logger and error printer
function print_error() {
    local error_code=$1
    local error_text="$2"
    local error_msg="There is an issue occurred, consider fixing it before rerunning $0"

    [[ "$error_text" ]] && printf "$(date '+%m/%d/%Y %H:%M:%S') : Error : %s \n" "$error_text" | tee -a "$log_file"
    printf "$(date '+%m/%d/%Y %H:%M:%S') : Error : %s \n" "$error_msg" | tee -a "$log_file"
    exit $error_code
}

# Some checks: - check if we have credentials for AWS IAM user; 
#              - check for .terraform directory existance;
#              - check if main.tf exist;
#              - check if user data script exist
function checks() {
    # check for AWS credentials set by operator via option for this script
    if [[ -z "$AWS_ACCESS_KEY_ID" ]] || [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        mylogger "Credential variable is not set. AWS_ACCESS_KEY_ID: '"$AWS_ACCESS_KEY_ID"', AWS_SECRET_ACCESS_KEY: '"$AWS_SECRET_ACCESS_KEY"', run '$0 -h' for help"
        return 1
    else
        mylogger "AWS credentials were found in global variables"
    fi
    
    # check if main.tf exist and readable
    if [[ ! -r main.tf ]]; then
        mylogger "Terraform infrastructure configuration file (main.tf) wasn't found in the working directory"
        return 2
    else
        mylogger "main.tf found in the working directory"
    fi

    # check if user data script exist in working directory
    if [[ ! -r entrypoint.sh ]]; then
        mylogger "User data script wasn't found in the working directory"
        return 3
    else
        mylogger "entrypoint.sh found in the working directory"
    fi

    return 0
}

# Run terraform validate to statically check and verify input tf file
# then check plan
function check_tf() {
    mylogger "Validating main.tf"
    terraform validate 2>&1 | tee -a "$log_file"

    if [[ $? == 0 ]]; then
        mylogger "No issues with syntax found"
    else
        mylogger "There is an issue with syntax occurred"
        return 1
    fi
    
    mylogger "Planning the actions"
    terraform plan 2>&1 | tee -a "$log_file"

    if [[ $? == 0 ]]; then
        mylogger "No issues with plan found, ready to deploy"
    else
        mylogger "There is an issue with plan occurred"
        return 2
    fi
}

# generate temporary database passwords
function cr_db_pwds() {
    mylogger "Generating temporary passwords for database for this run"
    
    # using data with nanoseconds, just in case
    export TF_VAR_db_pwd=$(date --rfc-3339=ns | sha512sum | awk '{print substr($1,12,12)}')
    export TF_VAR_db_manager_pwd=$(date --rfc-3339=ns | sha512sum | awk '{print substr($1,8,12)}')
    export TF_VAR_db_user_pwd=$(date --rfc-3339=ns | sha512sum | awk '{print substr($1,4,12)}')

    # check if passwords were collected and exported
    if [[ $TF_VAR_db_pwd ]] && [[ $TF_VAR_db_user_pwd ]] && \
        [[ $TF_VAR_db_manager_pwd ]]; then
        mylogger "All temporary passwords for database were successfully created and exported"
    else
        mylogger "There was an issue with creating temporary passwords"
        return 1
    fi

    return 0
}

# execute terraform apply
function create_infra() {
    mylogger "Attempting to create infrastructure"
    yes yes | terraform apply
    if [[ $? == 0 ]]; then
        mylogger "Infrastructure has been successfully created"
    else
        mylogger "An issue occurred while creating infrastructure"
        return 1
    fi
}

# destroy infrastructure, collect 
function destroy_infra() {
    # some simple checks if this is a correct infrastructure to destroy
    printf "Checking if we are about to destroy correct infrastructure\n"
    local test_db_sec=$(cat main.tf | awk '{if($0 ~ /terraform-br-test-db-strict-sec-group/) print "OK"}')
    local ubuntu_ami=$(cat main.tf | awk '{if($1 == "default" && $3 ~ /ami-0127d62154efde733/) print "OK"}')
    local nodes_ips=$(cat main.tf | awk '{if($0 ~ /data.aws_instances.nodes.public_ips/) print "OK"}')

    if [[ "$test_db_sec" == "OK" ]] && \
        [[ "$ubuntu_ami" == "OK" ]] && \
        [[ "$nodes_ips" == "OK" ]]; then
        printf "It looks like we are about to destroy correct infrastructure\n"
    else
        printf "It doesn't looks like this is correct main.tf, wont destroy this automatically, consider destroing it manually"
    fi

    # check for AWS credentials on destroy
    if [[ -z "$AWS_ACCESS_KEY_ID" ]] ||  [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        export AWS_ACCESS_KEY_ID="$i_arg"
        export AWS_SECRET_ACCESS_KEY="$s_arg"
        printf "AWS credentials were collected\n"
    fi

    printf "Collecting database passwords to be able to destroy rds instance\n"
    
    # collect and export temporary database passwords from running infrastructure
    export TF_VAR_db_pwd=$(terraform show | awk -F":" '{if($0 ~ /pgpass/ && $4 == "mradmin") print $5}' | awk '{print $1}')
    export TF_VAR_db_manager_pwd=$(terraform show | awk -F":" '{if($0 ~ /pgpass/ && $4 == "dbmanager") print $5}' | awk '{print $1}')
    export TF_VAR_db_user_pwd=$(terraform show | awk -F":" '{if($0 ~ /pgpass/ && $4 == "dbuser") print $5}' | awk '{print $1}')

    # execute 'terraform destroy'
    printf "Attempting to destroy infrastructure...\n"
    yes yes | terraform destroy

    if [[ $? == 0 ]]; then
        printf "Infrastructure has been destroyed\n"
    else
        printf "Failed to destroy infrastructure, consider destroing it manually\n"
        exit 1
    fi
}

# collect AWS credentials
function collect_aws_creds() {
    # collecting AWS credentials from script's arguments
    if [[ -n "$i_arg" ]] && [[ -n "$s_arg" ]]; then
        export AWS_ACCESS_KEY_ID="$i_arg"
        export AWS_SECRET_ACCESS_KEY="$s_arg"
        mylogger "AWS credentials enviromental variables were exported"
    fi
}

# main function
function main() {
    if [[ -z "$AWS_ACCESS_KEY_ID" ]] || [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        collect_aws_creds
    fi
    # check aws keys and main.tf 
    checks
    local checks_rc=$?

    if [[ $checks_rc == 0 ]]; then
        mylogger "No issues with AWS credentials were found"
    elif [[ $checks_rc == 1 ]]; then
        print_error 1 "AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) weren't found"
    elif [[ $checks_rc == 2 ]]; then
        print_error 1 "main.tf wasn't found, nothing to work with"
    elif [[ $checks_rc == 3 ]]; then
        print_error 1 "entrypoint.sh wasn't found, wont able to proceed with infrastructure creation"
    fi

    # create and export temporart database passwords
    cr_db_pwds
    local cr_db_pwds_rc=$?

    if [[ $db_pwds_rc == 1 ]]; then
        print_error 1 "Failed to create and export temporary database passwords, try to export them manually: 'export TF_VAR_db_pwd=', 'export TF_VAR_db_manager_pwd', 'export TF_VAR_db_user_pwd'"
    fi

    # run 'terraform validate' and 'terraform plan', check for return codes
    check_tf
    local checktf_rc=$?

    if [[ $checktf_rc == 0 ]]; then
        mylogger "All looks good, attempting to create infrastructure"
        # create infrastructure
        create_infra
    elif [[ $checktf_rc == 1 ]]; then
        print_error 1 "Failed to validate syntax"
    elif [[ $checktf_rc == 2 ]]; then
        print_error 1 "Failed to plan the actions"
    fi

    mylogger "Waiting 45 seconds till infrastructure comes up"
    sleep 45
    mylogger "Attempting to connect to the created server"
    curl $(terraform output node_public_ipv4 | awk -F'"' '{if($0 ~ /"/) print $2}')

    mylogger "Job is done."
}

# check if teraform executable is available for execution
if [[ ! -x $(which terraform) ]]; then
    printf "Error: terraform executable is not found, make sure it is downloaded and unzipped into the directory set in PATH variable\n" && exit 1
fi


# check if '.terraform' directory exits, if not -- attempt to `terraform init`
if [[ ! -d .terraform/ ]]; then
    printf "'.terraform' directory wasn't found in the current directory\n"
    printf "Attempting to init this working directory...\n"
    terraform init 2>&1
    if [[ $? == 0 ]]; then
        printf "Working directory sucessfully init'ed\n"
    else
        printf "There was an issue initing this working directory, consider fixing the issue manually\n" 
        exit 1
    fi
fi

# check for AWS credentials in global environments in case of no options
if [[ ! $1 ]]; then
    [[ -z "$AWS_ACCESS_KEY_ID" ]] || [[ -z "$AWS_SECRET_ACCESS_KEY" ]] && printf "Error: Credential variable is not set. AWS_ACCESS_KEY_ID: '%s', AWS_SECRET_ACCESS_KEY: '%s', run '$0 -h' for help\n" "$i_arg" "$s_arg" && exit 1
fi

# manage options and arguments
while getopts ":i:s:d:h" opt
    do
        case "$opt" in
            i) i_opt=true; i_arg=$OPTARG ;;
            s) s_opt=true; s_arg=$OPTARG ;;
            d) d_opt=true; [[ $OPTARG == "yes" ]] && destroy_infra || printf "Wont destroy infrastructure\n" && exit 1;;
            h) h_opt=true; print_usage ;;
            :) printf "Error: Option '-$OPTARG', requires an argument, run \'$0 -h\' for help\n" && exit 1 ;;
		    \?) printf "Error: Bad option: -$OPTARG, run \'$0 -h\' for help\n" && exit 1 ;;
        esac
    done

# create log file
log_file="$(mktemp "$0"-"$(whoami)"-"$(hostname)"-"$(date '+%Y_%m_%d-%H_%M_%S')".XXX.log)"

# run main function to rule them all
main

exit 0


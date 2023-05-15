#!/bin/bash

# This function validates input parameter ENV
validate_environment() {
  if ! [[ "$1" == "DEV" || "$1" == "QA" || "$1" == "BETA" || "$1" == "PROD" || "$1" == "DR" ]]; then
    echo "Invalid ENV argument value, it should DEV/QA/BETA/PROD/DR"
    show_script_usage_delete
    exit 1
  fi
}

# This function sets up all required variables
setup_env() {
  export app_name='AS'
  export app_environment=$1
  echo app_environment: $app_environment, app_name: $app_name

  # Setup environment specific variables from <ENV>.json file
  local __env_file=$cfn_dir/env/$app_environment/$app_environment.json
  get_json_property_value $__env_file region aws_region
  export aws_region
  echo aws_region: $aws_region
}

# Check whether script is called from repository root
export scripts_dir='./deployment/scripts'
export cfn_dir='./deployment/cfn'
export lambda_dir='./deployment/cfn/lambda'
export lambda_package_dir='./deployment/lambda_package'
if [[ "$(dirname $0)" != "$scripts_dir" ]]; then
  echo "This script must be called from repository root"
  exit 1
fi

# Load common functions
source ${scripts_dir}/helper/util.sh

# Check number of arguments
if [[ $# -ne 1 ]]; then
  show_script_usage_delete
  exit
fi

# Validate input parameters
validate_environment $1

# Setup environment
setup_env $1

# Delete stacks
delete_stacks ${cfn_dir}/env/stacks.json
echo "All stacks are deleted successfully"

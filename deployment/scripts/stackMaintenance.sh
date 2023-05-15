#!/bin/bash

# This function validates input parameter ENV
validate_environment() {
  if ! [[ "$1" == "DEV" || "$1" == "QA" || "$1" == "BETA" || "$1" == "PROD" || "$1" == "DR" ]]; then
    echo "Invalid ENV argument value, it should DEV/QA/BETA/PROD/DR"
    show_script_usage_stack_maintenance
    exit 1
  fi
}

# This function validates input parameter StackName
validate_input_stack_name() {
  local _stack_file=${cfn_dir}/env/stacks.json
  validate_stack_name ${_stack_file} $1 is_stack_name_found
  if [ "$is_stack_name_found" = "NO" ]; then
    echo "Invalid StackName argument value, $1 is not a valid stack name"
    show_script_usage_stack_maintenance
    exit 1
  fi
}

# This function validates input parameter IsActive
validate_action() {
  if ! [[ "$1" == "start" || "$1" == "stop" ]]; then
    echo "Invalid Action argument value, it should be start or stop"
    show_script_usage_stack_maintenance
    exit 1
  fi
}

# This function sets up all required variables
setup_env() {
  export app_name='GW'
  export app_environment=$1
  mn_stack_name=$2
  export is_maintenance='true'
  action=$3
  echo "app_environment: $app_environment, app_name: $app_name, mn_stack_name: $mn_stack_name, action:$action, is_maintenance: $is_maintenance"

  # Setup environment specific variables from <ENV>.json file
  local __env_file=$cfn_dir/env/$app_environment/$app_environment.json
  get_json_property_value $__env_file region aws_region
  export aws_region
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
if [[ $# -ne 3 ]]; then
  show_script_usage_stack_maintenance
  exit 1
fi

# Validate input parameters
validate_environment $1
validate_action $3

# Setup environment
setup_env $1 $2 $3

validate_input_stack_name $2

# Get image version
get_image_version ${cfn_dir}/env/stacks.json 1 0 image_version
export image_version

# Get active flag based on action type
is_active="$(get_active_flag ${action})"
echo "is_active: $is_active"
export is_active

stack_maintenance ${cfn_dir}/env/stacks.json $2
if [[ "$?" != "0" ]]; then
  echo "$2 stack maintenance failed"
  exit 1
fi

echo "$2 stack maintenance completed successfully"

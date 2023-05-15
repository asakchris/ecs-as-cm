#!/bin/bash

# This function validates input parameter ENV
validate_environment() {
  if ! [[ "$1" == "DEV" || "$1" == "QA" || "$1" == "BETA" || "$1" == "PROD" || "$1" == "DR" ]]; then
    echo "Invalid ENV argument value, it should DEV/QA/BETA/PROD/DR"
    show_script_usage_deploy
    exit 1
  fi
}

# This function validates input parameter IsActive
validate_active_flag() {
  if ! [[ "$1" == "true" || "$1" == "false" ]]; then
    echo "Invalid IsActive argument value, it should be true or false"
    show_script_usage_deploy
    exit 1
  fi
}

# This function sets up all required variables
setup_env() {
  export app_name='GW'
  export app_environment=$1
  export image_version=$2
  export is_active=$3
  echo "app_environment: $app_environment, app_name: $app_name, image_version: $image_version, is_active: $is_active"

  # Setup environment specific variables from <ENV>.json file
  local __env_file=$cfn_dir/env/$app_environment/$app_environment.json
  get_json_property_value $__env_file region aws_region
  export aws_region
  echo "aws_region: $aws_region"
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
  show_script_usage_deploy
  exit 1
fi

# Validate input parameters
validate_environment $1
validate_active_flag $3

# Setup environment
setup_env $1 $2 $3

# Exit if any of the stack is already in IN-PROGRESS state
validate_stacks ${cfn_dir}/env/stacks.json

# Deploy stacks, If script execution fails, it will retry again
deploy_stacks ${cfn_dir}/env/stacks.json
deploy_stacks_rc=$?
if [ "${deploy_stacks_rc}" -ne "0" ]; then
  echo "Deploy stack failed with exit code: ${deploy_stacks_rc}"
  exit 1
fi

echo "All stacks are deployed successfully"

# API Gateway will not deploy changes to the stages from second time, so run AWS CLI to
# manually deploy stage. It should run only during deployment, not start/stop
if [ -z "${is_maintenance}" ] || [ "${is_maintenance}" != "true" ]; then
  echo "Start deploying API Gateway Stage"
  deploy_api_gw_stage ${cfn_dir}/env/stacks.json
  api_gw_deploy_rc=$?
  if [ "${api_gw_deploy_rc}" -ne "0" ]; then
    echo "API Gateway deployment failed, so failing deployment: ${api_gw_deploy_rc}"
    exit 1
  fi
  echo "Deployed API Gateway Stage successfully"
fi

# CFN deploy command fails due to runtime error, then the command will not reach the service
# Hence, it will not start the tasks for ECS service
# So, check for ECS services without running tasks and fail the deployment if any
if [ "${is_active}" = "true" ]; then
  echo "ECS Services are started, so need to check for ECS services without running tasks"
  get_group_stack_property_value ${cfn_dir}/env/stacks.json 2 2 "stackName" l_stack_name
  echo "stack_name: ${l_stack_name}"
  get_ecs_servies_with_no_tasks "${l_stack_name}"
  task_check_rc=$?
  if [ "${task_check_rc}" -ne "0" ]; then
    echo "ECS Services without running tasks found, so failing deployment: ${task_check_rc}"
    exit 1
  fi
fi

echo "Deployment completed successfully"

#!/bin/bash

# This function returns JSON property value
# It takes 3 arguments
# (1) JSON filename with path
# (2) JSON property name
# (3) Variable name in which value to be assigned
get_json_property_value() {
  local __result_var=$3
  local _param_value=$(envsubst <$1 | jq -r .$2)
  eval $__result_var=$_param_value
}

# This function returns JSON property value of groupStacks array in stacks.json
# It takes 5 arguments
# (1) JSON filename with path
# (2) Stack Index
# (3) Group Stack Index
# (4) JSON property name
# (5) Variable name in which value to be assigned
get_group_stack_property_value() {
  local __result_var=$5
  local _property_value=$(envsubst <$1 | jq -r --argjson stack_index $2 --argjson group_index $3 --arg property $4 '.stacks[$stack_index].groupStacks[$group_index][$property]')
  eval $__result_var=$_property_value
}

# This function converts CFN parameter JSON file key and value into key=value separated by space
# It takes 1 argument
# (1) JSON filename with path
get_parameter_values() {
  local _parameters=$(envsubst <$1 | jq -r '. | to_entries | map("\(.key)=\(.value | tostring)") | join(" ")')
  echo "${_parameters}"
}

# This function converts given JSON file key and value into key="value" separated by space
# It takes 1 argument
# (1) JSON filename with path
convert_json_to_key_value() {
  local _parameters=$(envsubst <$1 | jq -r '. | to_entries | map("\(.key)=\"\(.value | tostring)\"") | join(" ")')
  echo "${_parameters}"
}

# This function installs required python dependencies and upload Lambda code into S3 bucket
# It takes 5 arguments
# (1) Directory in which Lambda python code available
# (2) Stack parameter file with path
# (3) Lambda package directory
# (4) Lambda zip filename prefix
cfn_package() {
  local _lambda_dir=$1 _parameter_file=$2 _pkg_dir=$3 _zip_prefix=$4
  get_json_property_value ${_parameter_file} LambdaS3Bucket lambda_s3_bucket
  get_json_property_value ${_parameter_file} LambdaS3Prefix lambda_s3_prefix
  echo "lambda_s3_bucket: ${lambda_s3_bucket}, lambda_s3_prefix: ${lambda_s3_prefix}"
  # Generate lambda zip filename by appending uuid
  lambda_zip_filename=${_zip_prefix}-$(uuidgen).zip
  export lambda_zip_filename
  echo "lambda_zip_filename: ${lambda_zip_filename}"
  # Update umask so that user, group and others have read access, it is required by Lambda
  umask 002
  # Remove Lambda package directory if exists already
  rm -rf ${_pkg_dir}
  # Create Lambda package directory and src directory underneath
  mkdir -p ${_pkg_dir}/src
  # Install Python requests package in src directory
  pip install requests -t ${_pkg_dir}/src
  # Copy Lambda python code into package src directory
  cp ${_lambda_dir}/*.py ${_pkg_dir}/src
  chmod 744 ${_pkg_dir}/src/*.py
  # Zip src directory
  (
    cd ${_pkg_dir}/src
    zip -r ../${lambda_zip_filename} .
  )
  chmod u+x ${_pkg_dir}/${lambda_zip_filename}
  # Upload zip file into S3
  aws s3 cp ${_pkg_dir}/${lambda_zip_filename} s3://${lambda_s3_bucket}/${lambda_s3_prefix}/${lambda_zip_filename}
  # Exit if upload to S3 bucket fails
  local _exit_code=$?
  if [[ "${_exit_code}" != "0" ]]; then
    echo "Lambda code upload to S3 bucket failed with exit code ${_exit_code}, so exiting"
    exit 1
  fi
}

# This function executes given CFN deploy command
# It takes 1 argument
# (1) AWS CloudFormation deploy/package command
execute_cfn() {
  echo "Executing $1 command"
  eval $1
}

# This function executes given CFN deploy command
# It takes 2 arguments
# (1) AWS CloudFormation stack name
# (2) AWS CloudFormation deploy/package command
execute_cfn_with_retry() {
  echo "Deploying $1 stack using command: $2"
  eval $2
  local _cfn_rc=$?
  echo "$1 stack completed with return code ${_cfn_rc}"
  if [ "${_cfn_rc}" -eq "255" ]; then
    echo "$1 stack failed with return code ${_cfn_rc} due to runtime error"
    # TODO: CFN deploy command fail while waiting for stack to complete is handled
    # deploy command fail while issuing stack create/update is not handled now
    # Get stack status with 30 retry attempts and wait for 30 seconds before each call
    # Retry if stack status is in-progress (2) or command fails (4)
    error_retry '2 4' 30 30 get_stack_status $1
    local _stack_status_rc=$?
    echo "Stack $1 status after retry: ${_stack_status_rc}"
    return ${_stack_status_rc}
  fi
  return ${_cfn_rc}
}

# Retry a command on a multiple exit codes, up to a max number of attempts
# Invocation:
#   err_retry exit_codes attempts sleep_sec <command>
# exit_codes: The exit codes to retry on, use space separated numeric codes
# attempts: The number of attempts to make
# sleep_sec: Sleep between attempts
error_retry() {
  local exit_codes=("$1")
  local attempts=$2
  local sleep_sec=$3
  echo "exit_codes: ${exit_codes}"
  echo "attempts: ${attempts}, sleep_sec: ${sleep_sec}"
  shift 3
  for attempt in $(seq 1 $attempts); do
    if [[ $attempt -gt 1 ]]; then
      echo "Attempt $attempt of $attempts"
    fi
    # Capture return codes under -o errexit
    "$@" && local rc=$? || local rc=$?
    # If return code is not part of retry exit codes, then exit
    if [[ ! " ${exit_codes[@]} " =~ " ${rc} " ]]; then
      return $rc
    fi
    # Exit if no of attempts exceeded
    if [[ $attempt -eq $attempts ]]; then
      return $rc
    fi
    echo "Sleeping for ${sleep_sec} seconds"
    sleep ${sleep_sec}
  done
}

# This function get CFN stack status
# It takes 1 argument
# (1) AWS CloudFormation stack name
# Returns
# 0 - stack create/update/delete completed successfully
# 1 - stack create/update/delete failed
# 2 - stack create/update/delete is in-progress
# 3 - stack doesn't exist
# 4 - stack status command failed
get_stack_status() {
  local _stack_status_response=$(aws --region $aws_region cloudformation describe-stacks --stack-name $1 --no-paginate)
  local _rc=$?
  # For new stack if deploy command fails then stack is not created so describe-stacks returns validation error
  if [ ${_rc} -eq 254 ]; then
    echo "$1 stack status command failed with validation error, stack doesn't exist"
    return 3
  elif [ ${_rc} -eq 0 ]; then
    local _stack_status=$(echo ${_stack_status_response} | jq -r '.Stacks[0].StackStatus')
    echo "stack_name: $1, _stack_status: ${_stack_status}"
    if [[ "${_stack_status}" == *"_IN_PROGRESS" ]]; then
      echo "$1 stack create/update/delete is in-progress"
      return 2
    elif [[ "${_stack_status}" == *"_FAILED" || "${_stack_status}" == *"ROLLBACK_COMPLETE" ]]; then
      echo "$1 stack create/update/delete failed"
      return 1
    else
      echo "$1 stack create/update/delete completed successfully"
      return 0
    fi
  else
    echo "$1 stack status command failed with non-zero exit code: ${_rc}"
    return 4
  fi
}

# This function waits for child processes to complete
# It takes 3 arguments
# (1) Child pids array length
# (2) Array of child pids
# (3) Array of stack names
# It returns 0 only if all stacks executed without failure
function wait_and_get_exit_codes() {
  local -a _children=("${@:2:$1}") _stacks=("${@:$1+2}")
  local _failed_stacks=()
  for i in "${!_children[@]}"; do
    job="${_children[$i]}"
    echo "Waiting for ${_stacks[$i]} stack to complete ${job}..."
    local _code=0
    wait ${job} || _code=$?
    if [[ "${_code}" != "0" ]]; then
      echo "${_stacks[$i]} stack failed with exit code ${_code}"
      _failed_stacks+=("${_stacks[$i]}")
    fi
  done
  local _exit_code=0
  if ((${#_failed_stacks[@]} > 0)); then
    _exit_code=1
    echo "Following stacks failed: ${_failed_stacks[@]}"
  fi
  return "${_exit_code}"
}

# This function deploy stacks, it picks one stack group at a time and run all stacks in that group in parallel
# It does not process next group if any stack failed in current group
# If IsActive is false it processes group in reverse order
# It takes 1 argument
# (1) stacks.json filename with path
deploy_stacks() {
  local _stack_file=$1

  local _cfn_tags_file=$(envsubst <${_stack_file} | jq -r .cfnTagsFile)
  echo "_cfn_tags_file: ${_cfn_tags_file}"

  local _length=$(jq -r '.stacks | length' ${_stack_file})
  let _length=_length-1
  echo "_length: ${_length}"

  local _start=0
  local _end=${_length}
  local _increment=1
  echo "is_active: ${is_active}, is_maintenance: ${is_maintenance}"
  if [ "${is_active}" = "false" ] && [ "${is_maintenance}" = "true" ]; then
    _start=${_length}
    _end=0
    _increment=-1
  fi
  echo "_start: $_start, _increment: $_increment, _end: $_end"

  for i in $(eval echo "{${_start}..${_end}..${_increment}}"); do
    deploy_stack_group_parallel ${_stack_file} $i ${_cfn_tags_file}
    if [[ "$?" != "0" ]]; then
      echo "Group $i stack failed"
      return 1
    fi
  done
}

# This function deploys CFN templates in given group stacks in parallel
# It takes 2 arguments
# (1) stacks.json filename with path
# (2) Group stacks array index
# (3) CFN template tags file name with path
deploy_stack_group_parallel() {
  local _stack_file=$1
  local _index=$2
  local _cfn_tags_file=$3

  local _length=$(jq -r --argjson index ${_index} '.stacks[$index].groupStacks | length' ${_stack_file})
  let _length=_length-1
  echo "_grp_length: ${_length}"

  local _group_child_pids=()
  local _group_stacks=()
  for j in $(seq 0 ${_length}); do
    get_group_stack_property_value ${_stack_file} ${_index} $j "stackName" stack_name
    get_group_stack_property_value ${_stack_file} ${_index} $j "isLambdaStack" is_lambda_stack
    get_group_stack_property_value ${_stack_file} ${_index} $j "templateFile" template_file
    get_group_stack_property_value ${_stack_file} ${_index} $j "paramFile" param_file
    get_group_stack_property_value ${_stack_file} ${_index} $j "lambdaDir" lambda_directory
    get_group_stack_property_value ${_stack_file} ${_index} $j "lambdaPackageDir" lambda_package_directory
    get_group_stack_property_value ${_stack_file} ${_index} $j "lambdaZipFileNamePrefix" lambda_zip_filename_prefix
    echo stackIndex: ${_index}, groupIndex: $j, stack_name: $stack_name, is_lambda_stack: $is_lambda_stack, \
    template_file: $template_file, param_file: $param_file, lambda_directory: $lambda_directory, \
    lambda_package_directory: $lambda_package_directory, lambda_zip_filename_prefix: $lambda_zip_filename_prefix

    # If it is Lambda stack and it is invoked from maintenance script, then skip stack
    if [ "${is_lambda_stack}" = "true" ] && [ "${is_maintenance}" = "true" ]; then
      echo "Skipping ${stack_name} stack because it is Lambda stack and invoked from maintenance script"
      continue
    fi

    # If it is Lambda stack, upload python code to S3
    if [ "${is_lambda_stack}" = "true" ]; then
      cfn_package ${lambda_directory} ${param_file} ${lambda_package_directory} ${lambda_zip_filename_prefix}
    fi

    # Get parameter overrides for given stack
    param_values="$(get_parameter_values ${param_file})"
    # Get CFN template tags
    export p_cfn_stack_name=${stack_name}
    cfn_tags="$(convert_json_to_key_value ${_cfn_tags_file})"
    # Run deploy command in parallel and collect child pid
    local _deploy_command="aws --region $aws_region cloudformation deploy --template-file ${template_file} --stack-name ${stack_name} --parameter-overrides ${param_values} --tags ${cfn_tags} --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset"
    execute_cfn_with_retry $stack_name "${_deploy_command}" &
    _group_child_pids+=("$!")
    _group_stacks+=("${stack_name}")
    sleep 3
  done

  local _pid_array_length=${#_group_child_pids[@]}
  echo "_pid_array_length: ${_pid_array_length}"
  #  Wait for for group stacks to complete
  if [ "${_pid_array_length}" -gt 0 ]; then
    wait_and_get_exit_codes "${#_group_child_pids[@]}" "${_group_child_pids[@]}" "${_group_stacks[@]}"
    local _group_stacks_return_code=$?
    # If any stack failed then exit
    if [ "${_group_stacks_return_code}" -ne "0" ]; then
      echo "Group ${_index} stacks failed so exiting, please look for failed stacks"
      return 1
    fi
  fi
  return 0
}

# This function find image version from deployed stack parameter
# First it finds stack from JSON based on stack index and stack group index
# It takes 3 arguments
# (1) stacks.json filename with path
# (2) Stack index
# (3) Stack group index
# (4) Variable name in which value to be returned
get_image_version() {
  local __result_var=$4
  get_group_stack_property_value $1 $2 $3 "stackName" stack_name
  echo "stack_name: ${stack_name}"
  local _image_version=$(aws --region $aws_region cloudformation describe-stacks --stack-name ${stack_name} --query "Stacks[0].Parameters[?ParameterKey=='ImageVersion'].ParameterValue" --output text)
  echo "_image_version: ${_image_version}"
  if [[ "${_image_version}" == "" ]]; then
    echo "Not able to find image version, so exiting, please check ${stack_name} stack parameter ImageVersion"
    exit 1
  fi
  eval $__result_var=${_image_version}
}

# It returns active flag based on action, returns true if action is start, otherwise returns false
# It takes 1 argument
# (1) Action
get_active_flag() {
  local _is_active='true'
  if [ "$1" = "stop" ]; then
    _is_active='false'
  fi
  echo "${_is_active}"
}

# This function deletes given CFN template stack
# It takes 1 argument
# (1) AWS cloudformation stack name
delete_cfn_stack() {
  echo "Deleting $1 stack..."
  aws --region $aws_region cloudformation delete-stack --stack-name $1
  echo "Waiting for $1 stack to be deleted, this may take few minutes..."
  aws --region $aws_region cloudformation wait stack-delete-complete --stack-name $1
}

# This function deletes CFN template stacks in given group stacks in parallel
# It takes 2 arguments
# (1) stacks.json filename with path
# (2) Group stacks array index
delete_stack_group_parallel() {
  local _stack_file=$1
  local _index=$2
  local _length=$(jq -r --argjson index ${_index} '.stacks[$index].groupStacks | length' ${_stack_file})
  let _length=_length-1
  echo "_grp_length: ${_length}"

  local _group_child_pids=()
  local _group_stacks=()
  for j in $(seq 0 ${_length}); do
    get_group_stack_property_value ${_stack_file} ${_index} $j "stackName" stack_name
    get_group_stack_property_value ${_stack_file} ${_index} $j "canBeDeleted" can_be_deleted
    echo "stackIndex: ${_index}, groupIndex: $j, stack_name: $stack_name, can_be_deleted: $can_be_deleted"

    # If stack marked as can not be deleted, skip it
    if [ "${can_be_deleted}" = "No" ]; then
      echo "Skipping ${stack_name} stack deletion because it is marked as can not be deleted"
      continue
    fi

    # Run delete stack command in parallel and collect child pid
    delete_cfn_stack "${stack_name}" &
    _group_child_pids+=("$!")
    _group_stacks+=("${stack_name}")
    sleep 3
  done

  local _pid_array_length=${#_group_child_pids[@]}
  echo "_pid_array_length: ${_pid_array_length}"
  #  Wait for for group stacks to complete
  if [ "${_pid_array_length}" -gt 0 ]; then
    wait_and_get_exit_codes "${#_group_child_pids[@]}" "${_group_child_pids[@]}" "${_group_stacks[@]}"
    local _group_stacks_return_code=$?
    # If any stack failed then exit
    if [ "${_group_stacks_return_code}" -ne "0" ]; then
      echo "Group ${_index} stacks failed so exiting, please look for failed stacks"
      exit 1
    fi
  fi
}

# This function delete stacks, it picks one stack group at a time and run all stacks in that group in parallel
# It does not process next group if any stack failed in current group
# It processes group in reverse order
# It takes 1 argument
# (1) stacks.json filename with path
delete_stacks() {
  local _stack_file=$1
  local _length=$(jq -r '.stacks | length' ${_stack_file})
  let _length=_length-1
  echo "_length: ${_length}"

  for i in $(eval echo "{${_length}..0..-1}"); do
    delete_stack_group_parallel ${_stack_file} $i
  done
}

# This function validates given stack name
# It takes 3 arguments
# (1) stacks.json filename with path
# (2) stack name to be validated
# (3) variable name in which result to be assigned
validate_stack_name() {
  local _stack_file=$1
  local _v_stack_name=$2
  local __result_var=$3
  echo "_stack_file: ${_stack_file}, _v_stack_name: ${_v_stack_name}, __result_var: ${__result_var}"
  local _length=$(jq -r '.stacks | length' ${_stack_file})
  let _length=_length-1
  echo "_length: ${_length}"
  local _match_found="NO"

  for i in $(seq 0 ${_length}); do
    local _grp_length=$(jq -r --argjson index ${i} '.stacks[$index].groupStacks | length' ${_stack_file})
    let _grp_length=_grp_length-1
    echo "_grp_length: ${_grp_length}"

    for j in $(seq 0 ${_grp_length}); do
      get_group_stack_property_value ${_stack_file} $i $j "stackName" stack_name
      echo "stack_name: ${stack_name}"
      if [ "${stack_name}" = "${_v_stack_name}" ]; then
        echo "${_v_stack_name} found in $i group at $j"
        _match_found="YES"
        break 2
      fi
    done
  done

  eval $__result_var=$_match_found
}

# This function is used for maintenance of stacks
# It takes 2 arguments
# (1) stacks.json filename with path
# (2) stack name for maintenance
stack_maintenance() {
  perform_stack_maintenance $1 $2
  if [[ "$?" != "0" ]]; then
    echo "$2 stack maintenance failed"
    return 1
  fi
}

# This function performs maintenance of stacks
# It takes 2 arguments
# (1) stacks.json filename with path
# (2) stack name for maintenance
perform_stack_maintenance() {
  local _stack_file=$1
  local _v_stack_name=$2
  echo "_stack_file: ${_stack_file}, _v_stack_name: ${_v_stack_name}"

  local _cfn_tags_file=$(envsubst <${_stack_file} | jq -r .cfnTagsFile)
  echo "_cfn_tags_file: ${_cfn_tags_file}"

  local _length=$(jq -r '.stacks | length' ${_stack_file})
  let _length=_length-1
  echo "_length: ${_length}"

  local _group_child_pids=()
  local _group_stacks=()
  for i in $(seq 0 ${_length}); do
    local _grp_length=$(jq -r --argjson index ${i} '.stacks[$index].groupStacks | length' ${_stack_file})
    let _grp_length=_grp_length-1
    echo "_grp_length: ${_grp_length}"

    for j in $(seq 0 ${_grp_length}); do
      get_group_stack_property_value ${_stack_file} $i $j "stackName" stack_name
      echo "stack_name: ${stack_name}"
      if [ "${stack_name}" = "${_v_stack_name}" ]; then
        echo "${_v_stack_name} found in $i group at $j"
        get_group_stack_property_value ${_stack_file} $i $j "isLambdaStack" is_lambda_stack
        get_group_stack_property_value ${_stack_file} $i $j "templateFile" template_file
        get_group_stack_property_value ${_stack_file} $i $j "paramFile" param_file
        echo stackIndex: ${_index}, groupIndex: $j, stack_name: $stack_name, is_lambda_stack: $is_lambda_stack, \
        template_file: $template_file, param_file: $param_file

        # If it is Lambda stack then skip stack
        if [ "${is_lambda_stack}" = "true" ]; then
          echo "Skipping ${stack_name} stack because it is Lambda stack"
          break 2
        fi

        # Get parameter overrides for given stack
        param_values="$(get_parameter_values ${param_file})"
        # Get CFN template tags
        export p_cfn_stack_name=${stack_name}
        cfn_tags="$(convert_json_to_key_value ${_cfn_tags_file})"
        # Run deploy command in parallel and collect child pid
        local _deploy_command="aws --region $aws_region cloudformation deploy --template-file ${template_file} --stack-name ${stack_name} --parameter-overrides ${param_values} --tags ${cfn_tags} --no-fail-on-empty-changeset"
        execute_cfn_with_retry $stack_name "${_deploy_command}" &
        _group_child_pids+=("$!")
        _group_stacks+=("${stack_name}")

        break 2
      fi
    done
  done

  local _pid_array_length=${#_group_child_pids[@]}
  echo "_pid_array_length: ${_pid_array_length}"
  # Wait for for group stacks to complete
  if [ "${_pid_array_length}" -gt 0 ]; then
    wait_and_get_exit_codes "${#_group_child_pids[@]}" "${_group_child_pids[@]}" "${_group_stacks[@]}"
    local _group_stacks_return_code=$?
    # If any stack failed then exit
    if [ "${_group_stacks_return_code}" -ne "0" ]; then
      echo "Group ${_index} stacks failed so exiting, please look for failed stacks"
      return 1
    fi
  fi
  return 0
}

# This function add tags to Cloud Watch Log Groups of given ECS Cluster
# It takes 3 arguments
# (1) Any ECS stack name in given cluster
# (2) ECS stack parameter of ECS Cluster name
# (3) ECS stack parameter of App Id
# (4) ECS stack parameter of Business Unit
# (5) ECS stack parameter of Environment
# (6) ECS stack parameter of Platform
# (7) ECS stack parameter of Support Group
add_cw_log_group_tags() {
  local _parameters=$(aws --region $aws_region cloudformation describe-stacks --stack-name $1 --query "Stacks[0].Parameters")
  local _ecs_cluster_name=$(echo ${_parameters} | jq -r --arg CLUSTER_NAME "$2" '.[] | select (.ParameterKey==$CLUSTER_NAME) | .ParameterValue')
  local _app_id=$(echo ${_parameters} | jq -r --arg APP_ID "$3" '.[] | select (.ParameterKey==$APP_ID) | .ParameterValue')
  local _business_unit=$(echo ${_parameters} | jq -r --arg BU "$4" '.[] | select (.ParameterKey==$BU) | .ParameterValue')
  local _environment=$(echo ${_parameters} | jq -r --arg PENV "$5" '.[] | select (.ParameterKey==$PENV) | .ParameterValue')
  local _platform=$(echo ${_parameters} | jq -r --arg PLFM "$6" '.[] | select (.ParameterKey==$PLFM) | .ParameterValue')
  local _support_group=$(echo ${_parameters} | jq -r --arg SPRT "$7" '.[] | select (.ParameterKey==$SPRT) | .ParameterValue')
  echo "_ecs_cluster_name: ${_ecs_cluster_name}, _app_id: ${_app_id}, _business_unit: ${_business_unit}, _environment: ${_environment}, _platform: ${_platform}, _support_group: ${_support_group}"

  local _service_list=$(aws --region ${aws_region} ecs list-services --cluster ${_ecs_cluster_name})
  #echo "_service_list: ${_service_list}"
  local _length=$(echo ${_service_list} | jq -r '.serviceArns | length')
  echo "No of ECS services: ${_length}"
  let _length=_length-1
  for s_counter in $(seq 0 ${_length}); do
    local _service_arn=$(echo ${_service_list} | jq -r --argjson idx ${s_counter} '.serviceArns[$idx]')
    local _td_arn=$(aws --region ${aws_region} ecs describe-services --cluster ${_ecs_cluster_name} --services ${_service_arn} | jq -r '.services[0].taskDefinition')
    local _log_group_name=$(aws --region ${aws_region} ecs describe-task-definition --task-definition ${_td_arn} | jq -r '.taskDefinition.containerDefinitions[0].logConfiguration.options."awslogs-group"')
    #echo "_service_arn: ${_service_arn}, _td_arn: ${_td_arn}"
    echo "_log_group_name: ${_log_group_name}"
    aws --region ${aws_region} logs tag-log-group --log-group-name ${_log_group_name} --tags Name=${_log_group_name},Owner=${_platform},AppID=${_app_id},BU=${_business_unit},Environment=${_environment},Support_Group="${_support_group}",Used_For=CONTAINER-LOGS
  done
}

# This function identify the ECS Services with no task running for given ECS Cluster
# It takes 2 arguments
# (1) ECS Cluster stack name in given cluster
# It returns 0 if all ECS services have running tasks otherwise returns 1
get_ecs_servies_with_no_tasks() {
  local _ecs_cluster_name=$(aws --region "${aws_region}" cloudformation describe-stacks --stack-name ${1} --query 'Stacks[0].Outputs[?OutputKey==`EcsClusterName`].OutputValue' --output text)
  echo "_ecs_cluster_name: ${_ecs_cluster_name}"

  local _service_list=$(aws --region "${aws_region}" ecs list-services --cluster "${_ecs_cluster_name}")
  #echo "_service_list: ${_service_list}"
  local _length=$(echo "${_service_list}" | jq -r '.serviceArns | length')
  echo "No of ECS services: ${_length}"
  ((_length--))
  local _no_tasks_array=()
  for s_counter in $(seq 0 "${_length}"); do
    local _service_arn=$(echo "${_service_list}" | jq -r --argjson idx "${s_counter}" '.serviceArns[$idx]')
    local _running_count=$(aws --region "${aws_region}" ecs describe-services --cluster "${_ecs_cluster_name}" --services "${_service_arn}" | jq -r '.services[0].runningCount')
    if [ "${_running_count}" -eq "0" ]; then
      #echo "No tasks running for service: ${_service_arn}"
      _no_tasks_array+=("${_service_arn}")
    fi
  done

  local _no_tasks_array_length=${#_no_tasks_array[@]}
  echo "_no_tasks_array_length: ${_no_tasks_array_length}"
  if [ "${_no_tasks_array_length}" -gt 0 ]; then
    echo "No tasks running for following ECS Services:"
    printf '%s\n' "${_no_tasks_array[@]}"
    return 1
  else
    echo "All ECS Services have tasks running"
    return 0
  fi
}

# Validate stacks before running deploy command, stacks should not be in IN-PROGRESS state
# It will exit if any of the stack is in IN-PROGRESS state
# It takes 1 argument
# (1) stacks.json filename with path
validate_stacks() {
  local _stack_file=$1
  # Get all stacks with status IN_PROGRESS
  local _create_in_progress_stacks=$(aws --region ${aws_region} cloudformation list-stacks --stack-status-filter CREATE_IN_PROGRESS --no-paginate | jq -r '.StackSummaries | map(.StackName) | join(",")')
  local _update_in_progress_stacks=$(aws --region ${aws_region} cloudformation list-stacks --stack-status-filter UPDATE_IN_PROGRESS --no-paginate | jq -r '.StackSummaries | map(.StackName) | join(",")')
  local _delete_in_progress_stacks=$(aws --region ${aws_region} cloudformation list-stacks --stack-status-filter DELETE_IN_PROGRESS --no-paginate | jq -r '.StackSummaries | map(.StackName) | join(",")')
  local _review_in_progress_stacks=$(aws --region ${aws_region} cloudformation list-stacks --stack-status-filter REVIEW_IN_PROGRESS --no-paginate | jq -r '.StackSummaries | map(.StackName) | join(",")')
  local _import_in_progress_stacks=$(aws --region ${aws_region} cloudformation list-stacks --stack-status-filter IMPORT_IN_PROGRESS --no-paginate | jq -r '.StackSummaries | map(.StackName) | join(",")')
  echo _create_in_progress_stacks: ${_create_in_progress_stacks}, _update_in_progress_stacks: ${_update_in_progress_stacks}, \
  _delete_in_progress_stacks: ${_delete_in_progress_stacks}, _review_in_progress_stacks: ${_review_in_progress_stacks}, \
  _import_in_progress_stacks: ${_import_in_progress_stacks}
  # Get stack group length
  local _length=$(jq -r '.stacks | length' ${_stack_file})
  let _length=_length-1
  echo "_length: ${_length}"
  for i in $(seq 0 ${_length}); do
    local _grp_length=$(jq -r --argjson index ${i} '.stacks[$index].groupStacks | length' ${_stack_file})
    let _grp_length=_grp_length-1
    echo "_length: ${_length}"
    for j in $(seq 0 ${_grp_length}); do
      get_group_stack_property_value ${_stack_file} $i $j "stackName" stack_name
      echo "stack_name: ${stack_name}"
      if [[ "${_create_in_progress_stacks}" == *"${stack_name}"* || "${_update_in_progress_stacks}" == *"${stack_name}"* || "${_delete_in_progress_stacks}" == *"${stack_name}"* || "${_review_in_progress_stacks}" == *"${stack_name}"* || "${_import_in_progress_stacks}" == *"${stack_name}"* ]]; then
        echo "${stack_name} is already IN-PROGRESS state, so exiting"
        exit 1
      fi
    done
  done
}

# This function performs rolling restart of tasks in ECS services of given stack
# It takes 1 argument
# (1) stack name for rolling restart
rolling_restart() {
  local _v_stack_name=$1
  echo _v_stack_name: ${_v_stack_name}

  # Get ECS cluster and service name from CFN stack outputs
  local _v_ecs_cluster_name=$(aws --region ${aws_region} cloudformation describe-stacks --stack-name ${_v_stack_name} --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text)
  if [ -z "${_v_ecs_cluster_name}" ]; then
    echo "Unable to find ECS cluster name, ClusterName output is missing in ${_v_stack_name} stack"
    return 1
  fi
  local _v_ecs_service_name=$(aws --region ${aws_region} cloudformation describe-stacks --stack-name ${_v_stack_name} --query "Stacks[0].Outputs[?OutputKey=='ServiceName'].OutputValue" --output text)
  if [ -z "${_v_ecs_service_name}" ]; then
    echo "Unable to find ECS service name, ServiceName output is missing in ${_v_stack_name} stack"
    return 1
  fi
  echo "_v_ecs_cluster_name: ${_v_ecs_cluster_name}, _v_ecs_service_name: ${_v_ecs_service_name}"

  # Restart all tasks in ECS service update service force new deployment flag
  local _v_rr_response=$(aws --region ${aws_region} ecs update-service --force-new-deployment --cluster ${_v_ecs_cluster_name} --service ${_v_ecs_service_name})
  local _v_rr_rc=$?
  if [[ "${_v_rr_rc}" != "0" ]]; then
    echo "Rolling restart command failed"
    return 1
  fi

  # Wait for rolling restart to complete
  aws --region ${aws_region} ecs wait services-stable --cluster ${_v_ecs_cluster_name} --services ${_v_ecs_service_name}
  local _v_wait_rr_rc=$?
  local retry_count=0
  echo "Exit Code for Wait Services-Stable is ${_v_wait_rr_rc}"
  while [ "${_v_wait_rr_rc}" == "255" ] && [ ${retry_count} -lt 4 ]; do
    retry_count=$(expr $retry_count + 1)
    echo "Re-trying wait command again as it is timed out. Retry count is $retry_count"
    aws --region ${aws_region} ecs wait services-stable --cluster ${_v_ecs_cluster_name} --services ${_v_ecs_service_name}
    _v_wait_rr_rc=$?
  done
  if [[ "${_v_wait_rr_rc}" != "0" ]]; then
    echo "Rolling restart failed, check ${_v_ecs_service_name} ECS service events for more details"
    return 1
  fi
}

# This function deploys API Gateway stage
# It takes 1 arguments
# (1) stacks.json filename with path
deploy_api_gw_stage() {
  local _stack_file=$1
  echo "_stack_file: ${_stack_file}, _v_stack_name: ${_v_stack_name}"

  local _current_date=$(date)
  echo "_current_date: ${_current_date}"

  local _cfn_tags_file=$(envsubst <"${_stack_file}" | jq -r .cfnTagsFile)
  echo "_cfn_tags_file: ${_cfn_tags_file}"

  local _length=$(jq -r '.stacks | length' "${_stack_file}")
  ((_length--))
  echo "_length: ${_length}"

  local _return_code=0
  for i in $(seq 0 "${_length}"); do
    local _grp_length=$(jq -r --argjson index "${i}" '.stacks[$index].groupStacks | length' "${_stack_file}")
    ((_grp_length--))
    echo "_grp_length: ${_grp_length}"

    for j in $(seq 0 "${_grp_length}"); do
      get_group_stack_property_value "${_stack_file}" "${i}" "${j}" "isApiGwStack" is_api_gw_stack
      echo "is_api_gw_stack: ${is_api_gw_stack}"

      if [ "${is_api_gw_stack}" = "true" ]; then
        get_group_stack_property_value "${_stack_file}" "${i}" "${j}" "stackName" v_stack_name
        echo "v_stack_name: ${v_stack_name}"

        local _v_api_gw_id=$(aws --region "${aws_region}" cloudformation describe-stacks --stack-name "${v_stack_name}" --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayId'].OutputValue" --output text)
        echo "_v_api_gw_id: ${_v_api_gw_id}"
        local _v_api_gw_stage_name=$(aws --region "${aws_region}" cloudformation describe-stacks --stack-name "${v_stack_name}" --query "Stacks[0].Outputs[?OutputKey=='ApiGwStageName'].OutputValue" --output text)
        echo "_v_api_gw_stage_name: ${_v_api_gw_stage_name}"

        aws --region "${aws_region}" apigateway create-deployment --rest-api-id "${_v_api_gw_id}" --stage-name "${_v_api_gw_stage_name}" --description "Deployed from CLI on ${_current_date}"
        _aws_command_rc=$?
        echo "_aws_command_rc: ${_aws_command_rc}"
        if [ ${_aws_command_rc} -ne 0 ]; then
          echo "API Gateway deployment failed for ${_v_api_gw_id}"
          _return_code=${_aws_command_rc}
        fi
      fi
    done
  done

  return ${_return_code}
}

# This function shows how to invoke deploy script
show_script_usage_deploy() {
  echo -e "\n************************************************************************************************"
  echo -e "$(date) Script error : Incorrect usage"
  echo -e "Script Usage:"
  echo -e "\t ./deployStack.sh <ENV> <ImageVersion> <IsActive>\n"
  echo -e "Pass 2 arguments to create/update Cloudformation stack"
  echo -e "(1) Environment Name (DEV/QA/BETA/PROD/DR)"
  echo -e "(2) Version of docker image"
  echo -e "(3) Is Active Environment? <true/false> If true, then it starts task for all ECS services, otherwise it will not start any tasks"
  echo -e "************************************************************************************************"
}

# This function shows how to invoke maintenance script
show_script_usage_maintenance() {
  echo -e "\n************************************************************************************************"
  echo -e "$(date) Script error : Incorrect usage"
  echo -e "Script Usage:"
  echo -e "\t ./maintenance.sh <ENV> <Action>\n"
  echo -e "Pass 2 arguments to start or stop all ECS service tasks"
  echo -e "(1) Environment Name (DEV/QA/BETA/PROD/DR)"
  echo -e "(2) Action (start/stop)"
  echo -e "************************************************************************************************"
}

# This function shows how to invoke stack maintenance script
show_script_usage_stack_maintenance() {
  echo -e "\n************************************************************************************************"
  echo -e "$(date) Script error : Incorrect usage"
  echo -e "Script Usage:"
  echo -e "\t ./stackMaintenance.sh <ENV> <StackName> <Action>\n"
  echo -e "Pass 3 arguments to start or stop all ECS service tasks"
  echo -e "(1) Environment Name (DEV/QA/BETA/PROD/DR)"
  echo -e "(2) CFN Stack Name"
  echo -e "(3) Action (start/stop)"
  echo -e "************************************************************************************************"
}

# This function shows how to invoke this delete script
show_script_usage_delete() {
  echo -e "\n************************************************************************************************"
  echo -e "$(date) Script error : Incorrect usage"
  echo -e "Script Usage:"
  echo -e "\t ./deleteStack.sh <ENV>\n"
  echo -e "Pass 1 argument to delete Cloudformation stack"
  echo -e "(1) Environment Name (DEV/QA/BETA/PROD/DR)"
  echo -e "************************************************************************************************"
}

# This function shows how to invoke stack maintenance script
show_script_usage_rolling_restart() {
  echo -e "\n************************************************************************************************"
  echo -e "$(date) Script error : Incorrect usage"
  echo -e "Script Usage:"
  echo -e "\t ./rollingRestart.sh <ENV> <StackName>\n"
  echo -e "Pass 2 arguments to for rolling restart of all tasks in an ECS service"
  echo -e "(1) Environment Name (DEV/QA/BETA/PROD/DR)"
  echo -e "(2) CFN Stack Name"
  echo -e "************************************************************************************************"
}

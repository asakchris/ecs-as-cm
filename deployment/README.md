##### Execute Cloudformation template using scripts
This script should be executed from repository root directory.
Install following before running the script:
- AWS CLI v2
- Python 3.8
- pip
- jq
###### Create/update all stacks
```commandline
./deployment/scripts/deployStack.sh <ENV> <IMAGE_VERSION> <IsActive>

ENV - DEV
ImageVersion - Version of docker image
IsActive - <true/false> If true, then it starts task for all ECS services, otherwise it will not start any tasks
```
###### Add auto-scaling policy
Cloudformation template doesn't support auto-scaling policy with metric math expression, so run below AWS CLI command:
```commandline
/usr/local/bin/aws application-autoscaling put-scaling-policy \
--region us-east-1 \
--policy-name DEV-AS-CONSUMER2-SCALING-POLICY \
--service-namespace ecs \
--resource-id service/DEV-AS-ECS-CLUSTER/DEV-AS-CONSUMER2-SERVICE \
--scalable-dimension ecs:service:DesiredCount \
--policy-type TargetTrackingScaling \
--target-tracking-scaling-policy-configuration file://deployment/cfn/env/DEV/Consumer2ScalingPolicy.json
```
###### Delete all stacks
```
./deployment/scripts/deleteStack.sh <ENV>

ENV - DEV
```
###### Start/stop tasks in all ECS Services
```commandline
./deployment/scripts/maintenance.sh <ENV> <Action>

ENV - DEV
Action - start/stop
```
###### Start/stop tasks in given CFN stack
```commandline
./deployment/scripts/stackMaintenance.sh <ENV> <StackName> <Action>

ENV - DEV
StackName - Name of CFN stack
Action - start/stop
```
###### Rolling restart of tasks in ECS Services in given CFN stack
```commandline
./deployment/scripts/rollingRestart.sh <ENV> <StackName>

ENV - DEV
StackName - Name of CFN stack
```

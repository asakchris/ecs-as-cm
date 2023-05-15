##### Execute Cloudformation template using scripts
This script should be executed from repository root directory.
Install following before running the script:
- AWS CLI v2
- Python 3.8
- pip
- jq
###### Create/update all stacks
```commandline
./deployStack.sh <ENV> <IMAGE_VERSION> <IsActive>

ENV - DEV
ImageVersion - Version of docker image
IsActive - <true/false> If true, then it starts task for all ECS services, otherwise it will not start any tasks
```
###### Delete all stacks
```
./deleteStack.sh <ENV>

ENV - DEV
```
###### Start/stop tasks in all ECS Services
```commandline
./maintenance.sh <ENV> <Action>

ENV - DEV
Action - start/stop
```
###### Start/stop tasks in given CFN stack
```commandline
./stackMaintenance.sh <ENV> <StackName> <Action>

ENV - DEV
StackName - Name of CFN stack
Action - start/stop
```
###### Rolling restart of tasks in ECS Services in given CFN stack
```commandline
./rollingRestart.sh <ENV> <StackName>

ENV - DEV
StackName - Name of CFN stack
```

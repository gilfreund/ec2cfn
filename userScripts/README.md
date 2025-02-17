The user scripts are tools to enable user actions with the need to go through the AWS console or remember all the syntax on the AWS CLI.
* [ ] : need to automake script build to use the same variable in the CFN stack.

### Instance launcher
[ecLaunch](./ecLaunch.sh)
Launch an instance based on the launch template providing the instance type and (optionally), AMI, username (to be included in the instance name) and project.
* [ ] TODO: Add needed local volume size (If needed)
### Connect ro instance
[ecConnect](./ecConnect.sh)
### Docker launcher
TODO
Launch a docker container with the parameters used in the batch system on the instance for monitoring 

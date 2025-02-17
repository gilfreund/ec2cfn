# User requirements
The following requirements are an amalgamation of requirements from various clients and projects. They are based around the need for a remote linux host(s) used for development and testing and batch instances and containers used for larger scale compute.   
## Linux shell
Users want a Linux shell where they can run code independently from their laptops shell (MacOS, Linux) or WSL (Windows). 
## Maintain Personal settings
Users want ot maintain their personal settings between sessions and across instances.
## Remote editing
Users want to access their code remotely (VScode or IntelliJ), or via ssh for debugging.
## Shared data
Users want to share data with other users in a common file system.
## Shared codebase
Users want to use the same code environment as their coworkers. Primarily for for library compatibility.
## Shared environment with user distinction
Users want to be able to identify which code or data was brought in by which user. users want to share some of their work environment with other on the fly, and not just via a code repository. Similar to a on-premiss linux hosts. 
## Additional interactive compute resources
Users want to launch additional compute resources on demand with a few steps as possible.  
## Users want to launch individual code environment (JupiterLab, RStudio) on demand. 
User will want those environment with access to a personal workspace, as well as shared spaces.
## Monitor instance performance
Users want to monitor instance performance to control costs and plan ahead.
## Docker container troubleshooting
Users want a method to troubleshot processes running in batch. To do so vis-a-vis the batch system is cumbersome.  
# AWS Offering
The following are aws services that can be used to address the needs 
## EC2 Instances
Single user environment (uid 1000, ec2-user on amazon linux, ubuntu on Ubuntu, etc.). No centralized local user in Linux, available on Windows instances only. Side note, Centralized linux user management is available in Azure.
## CloudShell 
Allows users logged in to the AWS console to run linux commands from a browser based command line. 
## SageMaker
An amazon offering for for ML, AI and data science. Includes a version of JupiterLabs. Will use instances for running notebooks and compute. Out of the box, does not interact directly with self managed ec2 instances. Side note: in Azure notebook editing does not require a paid instance,
## Workspace
Windows and Linux remote desktop VDI type solution. Can interact with instances and resources in its VPC. Requires a directory service and is one instance per user solution.  
# AWS Services limitations
* AWS services are build for one user per service instances, that user is usually ec2-user, uid 1000
* The AWS console uses a wizard style paradigm, which is cumbersome and not easily repeatable.

# Solutions outline
## VPC
Setup at least one Public subnet, to allow internet access. One to three private subnets. 
## Launch Template
Using a base instance with a launch template that include:
### Settings
* No base AMI (could be current Amazon Linux)
* No instance type
* Storage set to gp3
* No network / Availability Zone
* Instance profile allowing:
    * SSM access
    * Write to cloudwatch logs
    * control batch jobs
    * ECR Access
    * S3 access
* Security Group to include the instances
### UserData
#### Base software installation
Include a base of needed software to run the components in the boot process:
* git
* curl
* efs/nfs
* aws cli
* aws SAM
* cloudwatch agent  
#### Local Storage
##### Instance storage
If instance storage is available, format and mount it for the users. In case multiple instance storage volumes are available, bind them with LVM.
##### blank EBS attachment
For instances with not instances storage, and when local storage is needed, mount and format an EBS volume. [amazon-ebs-autoscale ](https://github.com/awslabs/amazon-ebs-autoscale) was a good tool for that, but it is no longer maintained. 
##### Mount data volumes
If needed, snapshots with data will be mounted as EBS volumes.
### Advances Software installation
#### Docker
In addition to the docker installation, the docker data will be move to the local storage 
#### CUDA and Nvidia drivers
If the instance includes an nvidia device, install current nvidia driver and cuda libraries. If other versions of CUDA are required, conda will be used to install them.
In addition, nvidia docker extensions will be installed. 
#### Cloudwatch agent
TODO: Setup initial cloudwatch monitoring (RAM, Processes, IO, GPU).
TODO: Create cloudwatch dashboard for the instance.
### Additional settings
#### EFS
Mount EFS for home directories and shared code and data
#### S3
Mount S3 buckets for data and archive access
## Additional infrastructure
### Storage
### Launch Group(s)
* A launch group for communal instance(s). 

## Additional process
### Volume cleanup
 
* [ ] TODO:In some scenarios mounted volumes are not deleted when the instance is terminated. A Lambda function will check for orphaned volumes and remove them.
### Cloudwatch dashboard cleanup 
* [ ] TODO: Remove Instance dashboard when the instance is deleted (or a certain time afterward)

## Scripts
### Users scripts

# Architectural decisions
* Do not use custom AMI, to avoid maintenance overhead.
# Known limitations
* Currently a single CFN file. 
* All code is done in the userdata section. Need to split into scripts and consider where to store the scripts.
* Hard coded CIDR. Need to parametrize and calculate subnets to maximize utilization. 
* Need a more dynamic allocation of storage resources (multiple S3 / EFS storafe)
# Open questions
* Assume that storage resources (S3, EFS) exist or include them in CFN?
* Need better tagging. 
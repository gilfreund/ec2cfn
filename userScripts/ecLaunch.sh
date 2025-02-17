#!/usr/bin/env bash

function getMetaData {
	local TOKEN
	TOKEN=$(curl --max-time 10 --silent --request PUT "http://169.254.169.254/latest/api/token"  \
		--header "X-aws-ec2-metadata-token-ttl-seconds: 21600")
	if [[ -n $TOKEN ]] ; then
		local tagValue
		tagValue=$(curl --max-time 10 --silent --fail \
			--header "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/$1) \
			&& echo "$tagValue"
	else
			exit 1
	fi
}

if [[ -z $AVAILABILITY_ZONE ]]; then 
	AVAILABILITY_ZONE=$(getMetaData "placement/availability-zone")
	export AVAILABILITY_ZONE
	export AWS_DEFAULT_REGION=${AVAILABILITY_ZONE:0:9}
fi

AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
AWS_REGION=$AWS_DEFAULT_REGION

LAUNCHTEMPLATE=$(aws ec2 describe-launch-templates \
    --launch-template-names CUDA \
    --query "LaunchTemplates[].LaunchTemplateId" \
    --output text) 
# shellcheck disable=SC2016
LAUNCHTEMPLATEVERSION='$Default'
PROJECT=none

# Usage output
usage() {
  echo "Usage: ${BASH_SOURCE[0]} [ -t | --type INSTANCETYPE ] [ -o | --owner OWNERTAG ] [ -p | --project PROJECT] [ -a | --ami AMI ]
        If unspcified:
        OWNERTAG is local user
        AMI is the default Amazon Linux AMI, specify 2023 for the newest version."
  exit 2
}

# Get viable subnets (zones)
subnets=$(aws --output text ec2 describe-subnets \
  --filters "Name=tag:Name,Values=*Private*" "Name=tag:deployment,Values=denovai" \
  --query "Subnets[*].SubnetId")
networkNumber=$((1 + $RANDOM % 3))
counter=0
for subnet in $subnets ; do
  counter=$((counter = counter + 1))
  if [[ $counter -eq $networkNumber ]] ; then
    break
  fi
done

# A Hack for MacOS incompatible getop
if command -v sw_vers ; then 
	if [[ $(sw_vers -productName) == macOS ]] ; then
		if [[ -d /usr/local/opt/gnu-getopt/bin ]] ; then
      # for Intel Mac
			PATH="/usr/local/opt/gnu-getopt/bin:$PATH"
  	elif [[ -d /opt/homebrew/opt/gnu-getopt/bin ]] ; then
      # For Apple Silcon Mac
      PATH="/opt/homebrew/opt/gnu-getopt/bin:$PATH"
    else
    	echo you need to install gnu getopt
    	exit 1
  	fi
	fi
fi

# Get and check parameters
ARGS=$(getopt --name ec2launch \
              --options 't:o:p:a:' \
              --longoptions 'type:,owner:,project:,ami:' -- "$@")

VALID_ARGUMENTS="$?"
if [[ "$VALID_ARGUMENTS" -gt "0" ]]; then
  usage
fi
eval "set -- $ARGS"
while true; do
    case $1 in
      -t|--type)
            INSTANCETYPE=${2}; shift 2;;
      -o|--owner)
            OWNERTAG=$2; shift 2;;
      -p|--project)
            PROJECT=$2; shift 2;;
      -a|--ami)
            IMAGEID=$2; shift 2;;
      --)  shift; break;;
      *)   echo "option $1 is unknown" ; usage; exit 1;;           # error
    esac
done

if [[ -z $INSTANCETYPE ]] ; then
  echo no instance type provided
  usage
fi

# shellcheck source=path/to/file
# Get IAM user          
if [[ -z $OWNERTAG ]] ; then
  OWNERTAG=$(whoami)
fi
# Get Requested instance information:
while read -r Architecture vcpu Memory StorageTotal StorageDiskSize StorageDiskCount StorageDiskNVME GPU_Manufacturer GPU_Name GPU_Number GPU_Memory FPGA_Manufacturer FPGA_Name FPGA_Number FPGA_Memory INF_Manufacturer INF_Name INF_Number SupportedVirtualizationType ; do

  echo "Requested $Architecture Instance with $vcpu vCPU, $Memory Memory"
  if [[ $StorageDiskCount -gt 0 ]] ; then
    echo "The $INSTANCETYPE has $StorageDiskCount x $StorageDiskSize GB disks, Total of $StorageTotal of instance storage, NVME is $StorageDiskNVME"
    for ((disk = 1 ; disk <= StorageDiskCount ; disk++)); do
      printf -v DiskLetter "\x$(printf %x $((${disk}+97)))"
      ephemeral=$((disk - 1))
      if [[ $disk -eq 1 ]] ; then
        DiskMapping="DeviceName=/dev/sd$DiskLetter,VirtualName=ephemeral$ephemeral"
      elif [[ $disk -gt 1 ]] ; then
        DiskMapping="$DiskMapping DeviceName=/dev/sd$DiskLetter,VirtualName=ephemeral$ephemeral"
      fi
    done 
      extraParams="--block-device-mappings $DiskMapping"
  else
    echo "The $INSTANCETYPE has has no instance storage"
  fi

  excelerator="None"
  if [[ $GPU_Manufacturer != "None" ]] ; then
    excelerator="$GPU_Manufacturer"
    echo "and $GPU_Number $GPU_Manufacturer $GPU_Name and $GPU_Memory Memory"
  elif [[ $FPGA_Manufacturer != "None" ]]; then
    excelerator="FPGA"
    echo "and $FPGA_Number $FPGA_Manufacturer $FPGA_Name and $FPGA_Memory Memory"
  elif [[ $INF_Manufacturer != "None" ]]; then
    excelerator="Inference"
    echo "and $FPGA_Number $INF_Number $INF_Name"
  else
    excelerator="None"
  fi

  ## Get AMI
  case $Architecture in
    i386 | x86_64)
      case $excelerator in
        NVIDIA | Inference)
          ## For accelerated see https://aws.amazon.com/releasenotes/aws-deep-learning-ami-catalog/
          if [[ $IMAGEID == "2023" ]] ; then
            IMAGEID=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
              --query Parameter.Value --output text)
          else
            IMAGEID=$(aws ec2 describe-images \
              --owners amazon \
              --filters 'Name=name,Values=Deep?Learning?Base?AMI?(Amazon?Linux?2)?Version???.?' "Name=state,Values=available" \
              --query "reverse(sort_by(Images,&CreationDate))[:1].ImageId" --output text)
          fi
          NAMEPREFIX="GPU"
          ;;      
        None)
          if [[ $IMAGEID == "2023" ]] ; then
            IMAGEID=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
              --query Parameter.Value --output text)
          else
            IMAGEID=$(aws ec2 describe-images \
            --owners amazon \
            --filters "Name=name,Values=amzn2-ami-$SupportedVirtualizationType-2.0.????????.?-$Architecture-gp2" "Name=state,Values=available" \
            --query "reverse(sort_by(Images,&CreationDate))[:1].[ImageId]" --output text)
          fi
          NAMEPREFIX="CPU"
          ;;
        *)
          echo "No support for $excelerator on $Architecture yet, exiting"
          exit 0
          ;;
      esac
      ;;
    arm64)
      echo "No Support for arm64 yet, exiting"
      exit 0
      # case $excelerator in
      #   NVIDIA)
      #     IMAGEID=$(aws ec2 describe-images \
      #       --owners amazon \
      #       --filters "Name=name,Values=Deep Learning AMI*" "Name=state,Values=available" \
      #       --query 'reverse(sort_by(Images,&CreationDate))[:1].[ImageId]')
      #     ;;
      #   None)
      #     IMAGEID=$(aws ec2 describe-images \
      #       --owners amazon \
      #       --filters "Name=name,Values=amzn2-ami-$SupportedVirtualizationType-2.0.????????.?-$Architecture-gp2" 'Name=state,Values=available' \
      #       --query 'reverse(sort_by(Images,&CreationDate))[:1].[ImageId]')
      #     ;;
      #   *)
      #     echo "No support for $excelerator on $Architecture yet, exiting"
      #     exit 0
      #     ;;
      # esac
      ;;
    x86_64_mac)
      echo "No Support for Mac X64 yet, exiting"
      exit 0
      ;;
    *)
      echo "Unknown architecture, exiting"
      exit 0
      ;;
  esac

done < <(aws --output text ec2 describe-instance-types --instance-types $INSTANCETYPE \
    --query InstanceTypes[].[ProcessorInfo.SupportedArchitectures[0],VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB,InstanceStorageInfo.TotalSizeInGB,InstanceStorageInfo.Disks[0].SizeInGB,InstanceStorageInfo.Disks[0].Count,InstanceStorageInfo.NvmeSupport,GpuInfo.Gpus[0].Manufacturer,GpuInfo.Gpus[0].Name,GpuInfo.Gpus[0].Count,GpuInfo.TotalGpuMemoryInMiB,FpgaInfo.Fpgas[0].Manufacturer,FpgaInfo.Fpgas[0].Name,FpgaInfo.Fpgas[0].Count,FpgaInfo.TotalFpgaMemoryInMiB,InferenceAcceleratorInfo.Accelerators[0].Manufacturer,InferenceAcceleratorInfo.Accelerators[0].Name,InferenceAcceleratorInfo.Accelerators[0].Count,SupportedVirtualizationTypes[0]])

if [[ -n $LAUNCHTEMPLATEVERSION ]]; then
  LAUNCHTEMPLATEVERSION=",Version=$LAUNCHTEMPLATEVERSION"
fi


InstanceID=$(aws --output text ec2 run-instances $extraParams \
  --launch-template LaunchTemplateId=${LAUNCHTEMPLATE}${LAUNCHTEMPLATEVERSION} \
  --image-id $IMAGEID \
  --instance-type $INSTANCETYPE \
  --subnet-id $subnet  --no-associate-public-ip-address \
  --block-device-mappings Ebs={VolumeSize=30},DeviceName=/dev/xvda \
  --tag-specifications \
  	"ResourceType=instance,Tags=[{Key=Name,Value=$OWNERTAG-$NAMEPREFIX},{Key=creator,Value=$OWNERTAG},{Key=deployment,Value=denovai},{Key=Project,Value=$PROJECT}]" \
  	"ResourceType=volume,Tags=[{Key=Name,Value=$OWNERTAG-$NAMEPREFIX},{Key=creator,Value=$OWNERTAG},{Key=deployment,Value=denovai},{Key=Project,Value=$PROJECT}]" \
  --query Instances[*].[InstanceId] )

echo "Launching Image $IMAGEID as Instance $InstanceID"



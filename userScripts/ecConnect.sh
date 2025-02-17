#!/usr/bin/env bash
# shellcheck disable=2086
# Quotes and aws command do not mix well

# TODO: 
## Need to fix vaiables. 
## Use SSM

function getInstances() {
    case $IpConnection in
        public)
            runAwsCommand --output text ec2 describe-instances \
            --filters Name=instance-state-name,Values=running Name=tag:"$TAG_KEY",Values="$TAG_VALUE" \
            --query "Reservations[*].Instances[*].[InstanceId,InstanceType,PublicIpAddress,PublicDnsName,Tags[?Key=='Name']|[0].Value]"
        ;;
        private)
            runAwsCommand --output text ec2 describe-instances \
            --filters Name=instance-state-name,Values=running Name=tag:"$TAG_KEY",Values="$TAG_VALUE" \
            --query "Reservations[*].Instances[*].[InstanceId,InstanceType,PrivateIpAddress,PrivateDnsName,Tags[?Key=='Name']|[0].Value]"
        ;;
        *)
            echo "No IP Connection type defined (IpConnection == $IpConnection)"
            exit
    esac

}

function connectTo() {
    local host=$1
    local num=0
    
    case $host in
        hostNumber)
            local hostNumber=$2
        ;;
        hostId)
            local hostId=$2
        ;;
    esac
    
    while IFS=$'\t' read -r InstanceId InstanceType PublicIpAddress PublicDnsName Name; do
        ((num = num + 1))
        if [[ $host == hostNumber ]] && [[ $hostNumber -eq $num ]]; then
            echo "you selected $hostNumber: $Name is $InstanceId (${InstanceType}) on $PublicDnsName (${PublicIpAddress})" && break
        elif [[ $host == hostId ]] && [[ $hostId == "$InstanceId" ]]; then
            echo "you selected $InstanceId: $Name (${InstanceType}) on $PublicDnsName (${PublicIpAddress})" && break
        else
            echo ""
        fi
    done < <(getInstances)
    if [[ -n "$SSH_KEY" ]] ; then
        PARAMS="$SSH_KEY"
    fi
    if [[ -n "$SSH_FORWARD" ]] ; then
        PARAMS="$PARAMS $SSH_KEY"
    fi
    if [[ -n $PARAMS ]] ; then
        ssh -tt $PARAMS "$SSH_USER"@"$PublicIpAddress" </dev/tty
    else
        ssh -tt "$SSH_USER"@"$PublicIpAddress" </dev/tty
    fi 
}

if [[ -z $1 ]] || [[ $1 == "public" ]] || [[ $1 == "private" ]]; then
    case $1 in
        public)
            IpConnection=public
        ;;
        private)
            IpConnection=private
        ;;
    esac
    echo "0:  Any host (rendom selection)"
    while IFS=$'\t' read -r InstanceId InstanceType PublicIpAddress PublicDnsName Name; do
        ((num = num + 1))
        echo "$num:  $Name is $InstanceId (${InstanceType}) on $PublicDnsName (${PublicIpAddress})"
    done < <(getInstances)
    echo "x:  Exit"
    while true; do
        read -rp 'Select host (0 for a random host, x to exit): ' hostNum
        if [[ $hostNum -gt $num ]] && [[ $hostNum != "x" ]]; then
            echo "Enter a vaule between 0 and $num or x"
            elif [[ $hostNum == "x" ]]; then
            echo "goodbye"
            exit 0
        else
            if [[ $hostNum -eq 0 ]]; then
                connectTo hostNumber $((1 + RANDOM % num))
            else
                connectTo hostNumber "$hostNum"
            fi
            exit 0
        fi
    done
else
    case $2 in
        public)
            IpConnection=public
        ;;
        private)
            IpConnection=private
        ;;
    esac
    case $1 in
        random)
            while IFS=$'\t' read -r InstanceId; do
                ((num = num + 1))
            done < <(getInstances)
            connectTo hostNumber $((1 + RANDOM % num))
        ;;
        i-*)
            connectTo hostId "$1"
        ;;
        [1-9])
            connectTo hostNumber "$1"
        ;;
        list)
            case $2 in
                public)
                    IpConnection=public
                ;;
                private)
                    IpConnection=private
                ;;
            esac
            getInstances
        ;;
        *)
            echo "Unknown option"
            exit 1
        ;;
    esac
fi

#!/usr/bin/env bash

# author: Jan Wrona, wrona@cesnet.cz

# Copyright (C) 2016 CESNET
#
# LICENSE TERMS
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name of the Company nor the names of its contributors
#    may be used to endorse or promote products derived from this
#    software without specific prior written permission.
#
# ALTERNATIVELY, provided that this notice is retained in full, this
# product may be distributed under the terms of the GNU General Public
# License (GPL) version 2 or later, in which case the provisions
# of the GPL apply INSTEAD OF those given above.
#
# This software is provided ``as is'', and any express or implied
# warranties, including, but not limited to, the implied warranties of
# merchantability and fitness for a particular purpose are disclaimed.
# In no event shall the company or contributors be liable for any
# direct, indirect, incidental, special, exemplary, or consequential
# damages (including, but not limited to, procurement of substitute
# goods or services; loss of use, data, or profits; or business
# interruption) however caused and on any theory of liability, whether
# in contract, strict liability, or tort (including negligence or
# otherwise) arising in any way out of the use of this software, even
# if advised of the possibility of such damage.


# TODO: gluster force?
#       don't download files


################################################################################
# initializations
################################################################################
set -e

trap_exit() {
        local RC=$?
        if [ "$RC" -ne 0 ]; then
                echo "Exitting with non-zero exit status $RC."
        fi
}
trap trap_exit EXIT

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        echo "Error: you need at least Bash 4.0 to run this script"
        exit 1
fi


################################################################################
# main function
################################################################################
main() {
        # initialization, default argument values
        declare -r DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        declare -g CONF_FILE="${DIR}/install.conf"
        declare -rg USER="hacluster"
        declare -rg GITHUB_BASE_URL="https://raw.githubusercontent.com/CESNET/SecurityCloud/master/"

        # check argument count
        if [ $# -lt 1 ]; then
                error "invalid arguments"
                echo
                print_usage
                return 1
        fi

        # parse arguments and check their validity
        parse_args "$@"
        check_args

        # parse configuration file and check mandatory keys etc.
        parse_config "${CONF_FILE}"
        check_config

        # replicate this script and the configuration file to all nodes
        if [ -z "${ARG_SSH}" ]; then
                # not running over SSH
                check_network

                for NODE in "${ALL_NODES[@]}"; do
                        scp -o "StrictHostKeyChecking no" \
                                "${0}" "${CONF_FILE}" \
                                "${NODE}:/tmp/" &>/dev/null
                done
        fi

        if [ -n "${ARG_SSH}" ]; then
                # running over SSH
                local OUT_PREFIX="[${ARG_COMMANDS[*]} on $(uname -n)]"
        else
                local OUT_PREFIX="[${ARG_COMMANDS[*]}]"
        fi

        # execute the supplied command (it is supposed to be a function defined
        # in this script)
        "${ARG_COMMANDS[@]}" 2>&1 | sed "s/^/${OUT_PREFIX} /"
        RC=${PIPESTATUS[0]} #return with commands's exit status, not sed's

        if [ -z "${ARG_SSH}" ]; then
                # not running over SSH
                if [ "$RC" -eq 0 ]; then
                        echo "It seems that everyting went OK!"
                else
                        echo "It seems that something went wrong!"
                        echo "You can try to run the script again."
                fi
        fi

        return "$RC"
}


################################################################################
# common functions
################################################################################
print_usage() {
        echo "Usage: $0 command [-c conf_file] [-h]"
}

print_help() {
        print_usage
        echo
        echo -e "Help:"
        echo -e "\tcommand           script sub-command"
        echo -e "\t-c conf_file      set configuration file [install.conf]"
        echo -e "\t-h                print help and exit"
        echo
        echo -e "Commands:"
        echo -e "\tcheck             check health of the cluster"
        echo -e "\tglusterfs         setup GlusterFS file system"
        echo -e "\tipfixcol          setup IPFIXcol framework"
        echo -e "\tfdistdump         setup fdistdump query tool"
        echo -e "\tstack             setup Corosync and Pacemaker stack"
}

warning() {
        echo -e "Warning: $1" >&2
        [ -z "$2" ] || echo -e "\tcommand: $2" >&2
        [ -z "$3" ] || echo -e "\toutput: $3" >&2
        [ -z "$4" ] || echo -e "\treturn code: $4" >&2
}

error() {
        echo -e "Error: $1" >&2
        [ -z "$2" ] || echo -e "\tcommand: $2" >&2
        [ -z "$3" ] || echo -e "\toutput: $3" >&2
        [ -z "$4" ] || echo -e "\treturn code: $4" >&2
}

str_strip() {
        # Return a copy of the string (first argument) with the leading and
        # trailing characters removed. The optional second argument is a set of
        # characters to be removed. If omitted, it defaults to removing
        # whitespace ([:space:]). The second argument is not a prefix or suffix;
        # rather, all combinations of its values are stripped. It can be any
        # combination of characters or character classes accepter by sed's
        # bracket expression.

        if [ "$#" -eq 0 ]; then
                return
        elif [ "$#" -eq 1 ]; then
                CHAR_SET="[:space:]"
        else
                CHAR_SET="$2"
        fi

        sed -e "s/^[${CHAR_SET}]*//" -e "s/[${CHAR_SET}]*$//" <<<"$1"
}

str_lstrip() {
        # Like str_strip, except that only the leading characters are removed.

        if [ "$#" -eq 0 ]; then
                return
        elif [ "$#" -eq 1 ]; then
                CHAR_SET="[:space:]"
        else
                CHAR_SET="$2"
        fi

        sed -e "s/^[${CHAR_SET}]*//" <<<"$1"
}

str_rstrip() {
        # Like str_strip, except that only the trailing characters are removed.

        if [ "$#" -eq 0 ]; then
                return
        elif [ "$#" -eq 1 ]; then
                CHAR_SET="[:space:]"
        else
                CHAR_SET="$2"
        fi

        sed -e "s/[${CHAR_SET}]*$//" <<<"$1"
}

parse_args() {
        declare SSH
        declare -a COMMANDS
        while [ $# -gt 0 ]; do
                case "${1}" in
                # arguments
                "-c")  # config file, requires one argument
                        shift
                        CONF_FILE="$1"
                        ;;
                "-h")  # help, no argument
                        print_help
                        exit 0
                        ;;

                # internal use only
                "-s")  # running over SSH, no argument
                        SSH=1
                        ;;

                *)  # anything else is a command
                        COMMANDS[${#COMMANDS[@]}]="${1}"
                        ;;
                esac
                shift
        done

        declare -gr ARG_SSH="$SSH"
        declare -agr ARG_COMMANDS=("${COMMANDS[@]}")
}

check_args() {
        # check configuration file existence
        if [ ! -f "${CONF_FILE}" ]; then
                error "cannot open configuration file \"${CONF_FILE}\""
                return 1
        fi

        if [ -z "$ARG_SSH" ]; then
                # not running over SSH, check user commands
                case "${ARG_COMMANDS[0]}" in
                check|glusterfs|ipfixcol|fdistdump|stack) ;;
                *)
                        error "unknown command \"${ARG_COMMANDS[0]}\""
                        return 1
                esac
        else
                # running over SSH, check internal commands
                case "${ARG_COMMANDS[0]}" in
                check_network|check_programs|check_libraries|check_vip) ;;
                gluster1_all|gluster2_one|gluster3_all) ;;
                ipfixcol1_all|ipfixcol2_one) ;;
                fdistdump1_all) ;;
                stack1_all|stack2_one) ;;
                *)
                        error "unknown internal command \"${ARG_COMMANDS[0]}\""
                        return 1
                esac
        fi
}

parse_config() {
        local KEY VALUE IFS="="

        while read -r KEY VALUE; do
                # strip whitespaces around the KEY and VALUE
                KEY="$(str_strip "$KEY")"
                VALUE="$(str_strip "$VALUE")"

                case "$KEY" in
                # definition of nodes
                "node_proxy") PRO_NODES[${#PRO_NODES[@]}]="$VALUE" ;;
                "node_subcollector") SUB_NODES[${#SUB_NODES[@]}]="$VALUE" ;;

                # GlusterFS options (paths)
                "gfs_conf_brick")
                        GFS_CONF_BRICK="$(str_rstrip "$VALUE" "/")" ;;
                "gfs_flow_primary_brick")
                        GFS_FLOW_PRIMARY_BRICK="$(str_rstrip "$VALUE" "/")" ;;
                "gfs_flow_backup_brick")
                        GFS_FLOW_BACKUP_BRICK="$(str_rstrip "$VALUE" "/")" ;;
                "gfs_conf_mount")
                        GFS_CONF_MOUNT="$(str_rstrip "$VALUE" "/")" ;;
                "gfs_flow_mount")
                        GFS_FLOW_MOUNT="$(str_rstrip "$VALUE" "/")" ;;

                # virtual (floating) IP address options
                "vip_address") VIP_ADDRESS="$VALUE" ;;
                "vip_prefix") VIP_PREFIX="$VALUE" ;;
                "vip_interface") VIP_INTERFACE="$VALUE" ;;
                esac
        done < <(grep "^[^=]*=" "$1")  # process substitution magic

        ALL_NODES=( "${SUB_NODES[@]}" "${PRO_NODES[@]}" )
}

check_config() {
        # check nodes definition
        if [ "${#ALL_NODES[@]}" -lt 2 ]; then
                error "configuration: at least two nodes are mandatory"
                return 1
        fi
        if [ "${#SUB_NODES[@]}" -lt 1 ]; then
                error "configuration: at least one subcollector node is mandatory"
                return 1
        fi

        # check GlusterFS options
        if [ -z "$GFS_CONF_BRICK" ]; then
                error "configuration: missing mandatory key \"gfs_conf_brick\""
                return 1
        fi
        if [ -z "$GFS_FLOW_PRIMARY_BRICK" ]; then
                error "configuration: missing mandatory key \"gfs_flow_primary_brick\""
                return 1
        fi
        if [ -z "$GFS_FLOW_BACKUP_BRICK" ]; then
                error "configuration: missing mandatory key \"gfs_flow_backup_brick\""
                return 1
        fi
        if [ -z "$GFS_CONF_MOUNT" ]; then
                error "configuration: missing mandatory key \"gfs_conf_mount\""
                return 1
        fi
        if [ -z "$GFS_FLOW_MOUNT" ]; then
                error "configuration: missing mandatory key \"gfs_flow_mount\""
                return 1
        fi

        # syntactically check virtual (floating) IP address options
        if [ -z "$VIP_ADDRESS" ]; then
                error "configuration: missing mandatory key \"vip_address\""
                return 1
        elif type ipcalc &>/dev/null && ! ipcalc -sc4 "$VIP_ADDRESS"; then
                error "configuration: vip_address: invalid IPv4 address \"$VIP_ADDRESS\""
                return 1
        fi
        if [[ -n "$VIP_PREFIX" && ! ( "$VIP_PREFIX" =~ ^-?[0-9]+$ && \
                "$VIP_PREFIX" -ge 0 && "$VIP_PREFIX" -le 32 ) ]]
        then
                error "configuration: vip_prefix: invalid prefix \"$VIP_PREFIX\""
                return 1
        fi

        return 0
}

ssh_exec() {
        if [ -n "${ARG_SSH}" ]; then
                error "recursive SSH exec"
                exit 1
        fi

        local BINARY="$(basename "$0")"
        local CONF_NAME="$(basename "${CONF_FILE}")"

        local CMD="$1"
        shift

        for NODE in "$@"; do
                echo "Connecting to ${NODE}."
                ssh -o "StrictHostKeyChecking no" -t \
                        "${NODE}" \
                        "/tmp/${BINARY}" "$CMD" -c "/tmp/${CONF_NAME}" -s
                echo
        done
}


################################################################################
# health checking functions
################################################################################
check() {
        ssh_exec check_network "${ALL_NODES[@]}"
        ssh_exec check_programs "${ALL_NODES[@]}"
        ssh_exec check_libraries "${ALL_NODES[@]}"
        ssh_exec check_vip "${ALL_NODES[@]}"
}

check_network() {
        local NODE
        for NODE in "${ALL_NODES[@]}"; do
                # test getnet ahosts
                if ! getent ahosts "$NODE" >/dev/null; then
                        error "unable to resolve \"$NODE\"" \
                              "getent ahosts $NODE"
                        return 1
                fi
                local LINE
                while read LINE; do
                        local ADDR=$(cut -d" " -f 1 <<<"$LINE")
                        if [[ "$ADDR" == 127.* || "$ADDR" == ::1* ]]; then
                                error "$NODE is mapped to localhost IP address \"$ADDR\""
                                return 1
                        fi
                done < <(getent ahosts "$NODE")

                # test ping
                if ! ping -c 1 "$NODE" >/dev/null; then
                        error "unable to ping $NODE" "ping -c 1 $NODE"
                        return 1
                fi

                # test SSH
                if ! ssh -o "StrictHostKeyChecking no" "$NODE" true; then
                        error "unable to SSH to $NODE"
                        return 1
                fi
        done
}

check_programs() {
        declare -ar PROGRAMS=(libnf-info ipfixcol corosync pacemakerd pcs
                              glusterd gluster ip hostname uname crm_attribute
                              xmllint chown)
        local PROG
        for PROG in "${PROGRAMS[@]}"; do
                # test presence of the program
                if ! type -f "$PROG" >/dev/null; then
                        error "program \"$PROG\" not found" "type -f $PROG"
                        return 1
                fi
        done

        # user existence test
        if ! getent passwd "$USER" >/dev/null; then
                error "user \"$USER\" doesn't exist" "getent passwd $USER"
                return 1
        fi

        # group existence test
        declare -r GROUP="$(id -gn "$USER")"
        if ! getent group "$GROUP" >/dev/null; then
                error "group \"$GROUP\" doesn't exist" "getent group $GROUP"
                return 1
        fi
}

check_libraries() {
        declare -ar LIBRARIES=(libnf libcpg)
        local LIB
        for LIB in "${LIBRARIES[@]}"; do
                # test presence of the library
                if ! ldconfig -p | grep "$LIB\." >/dev/null; then
                        error "library \"$LIB\" is not installed"
                              "ldconfig -p | grep \"$LIB\.\""
                        return 1
                fi
        done
}

check_vip() {
        # semantically check virtual (floating) IP address options
        if [ -n "$VIP_INTERFACE" ] && \
                ! ip link show "$VIP_INTERFACE" >/dev/null
        then
                error "interface \"$VIP_INTERFACE\" does not exist"
                return 1
        fi
}


################################################################################
# setup GlusterFS functions
################################################################################
glusterfs() {
        ssh_exec gluster1_all "${ALL_NODES[@]}"
        ssh_exec gluster2_one "${ALL_NODES[0]}"
        ssh_exec gluster3_all "${ALL_NODES[@]}"
}

gluster1_all() {
        # create directories for bricks
        mkdir -p "${GFS_CONF_BRICK}" "${GFS_FLOW_PRIMARY_BRICK}" \
                "${GFS_FLOW_BACKUP_BRICK}"
        # create directories for mount points
        mkdir -p "${GFS_CONF_MOUNT}" "${GFS_FLOW_MOUNT}"

        # check if glusterd is running
        if ! pgrep glusterd >/dev/null; then
                error "GlusterFS daemon is not running" "pgrep glusterd"
                return 1
        fi
        if ! netstat -tavn | grep "2400[7|8]" >/dev/null; then
                error "GlusterFS daemon is not running" \
                       "netstat -tavn | grep \"2400[7|8]\""
                return 1
        fi

        # download and install custom filter
        declare -r GFS_VERSION="$(gluster --version | head -1 | cut -d" " -f 2)"
        declare -r GFS_PATH="$(find /usr/ -type d -path \
                "/usr/lib*/glusterfs/${GFS_VERSION}")"
        declare -r FILTER_DIR="filter"
        declare -r FILTER_NAME="filter.py"

        mkdir -p "${GFS_PATH}/${FILTER_DIR}/"
        echo "Downloading custom GlusterFS filter"
        curl -sS "${GITHUB_BASE_URL}/gluster/${FILTER_NAME}" \
                >"${GFS_PATH}/${FILTER_DIR}/${FILTER_NAME}"
        chmod +x "${GFS_PATH}/${FILTER_DIR}/${FILTER_NAME}"
}

gluster2_one() {
        # create a trusted pool
        declare -a CONF_BRICKS
        declare -r STATE="peer in cluster"
        local NODE
        for NODE in "${ALL_NODES[@]}"; do
                gluster peer probe "$NODE"
                sleep 1

                # wait for desired peer state
                while gluster peer status \
                        | grep -i "state:" \
                        | grep -iv "$STATE" \
                        >/dev/null
                do
                        echo "waiting for \"$NODE\" to get into the \"$STATE\" state"
                        sleep 1
                done

                CONF_BRICKS[${#CONF_BRICKS[@]}]="${NODE}:${GFS_CONF_BRICK}"
        done

        # create configuration volume "conf"
        if gluster volume info conf >/dev/null; then
                echo "volume conf already exists"
        else
                echo "creating volume conf"
                gluster volume create conf replica ${#ALL_NODES[@]} \
                        "${CONF_BRICKS[@]}" force
                sleep 1

                # disable NFS
                gluster volume set conf nfs.disable true
                # set timeout to 10 seconds for faster reactions to failures
                gluster volume set conf network.ping-timeout 10
        fi
        # start configuration volume "conf"
        if gluster volume status conf >/dev/null; then
                echo "volume conf already started"
        else
                echo "starting volume conf"
                gluster volume start conf
        fi

        # create bricks specification for data volume "flow" (ring topology)
        declare -ir CNT=${#SUB_NODES[@]}
        declare -a FLOW_BRICKS
        for ((I=0; I<CNT; I++)); do
                # primary brick
                FLOW_BRICKS[${#FLOW_BRICKS[@]}]="${SUB_NODES[$I]}:${GFS_FLOW_PRIMARY_BRICK}"
                # secondary brick
                FLOW_BRICKS[${#FLOW_BRICKS[@]}]="${SUB_NODES[$(((I+1)%CNT))]}:${GFS_FLOW_BACKUP_BRICK}"
        done
        # create data volume "flow"
        if gluster volume info flow >/dev/null; then
                echo "volume flow already exists"
        else
                echo "creating volume flow"
                gluster volume create flow replica 2 "${FLOW_BRICKS[@]}" force

                # disable NFS
                gluster volume set flow nfs.disable true
                # set timeout to 10 seconds for faster reactions to failures
                gluster volume set flow network.ping-timeout 10
                # enable NUFA
                gluster volume set flow cluster.nufa enable
        fi
        # start data volume "flow"
        if gluster volume status flow >/dev/null; then
                echo "volume flow already started"
        else
                echo "starting volume flow"
                gluster volume start flow
        fi
}

gluster3_all() {
        # mount the volumes
        if mountpoint -q "$GFS_CONF_MOUNT"; then
                echo "volume conf already mounted"
        else
                echo "mounting volume conf"
                mount -t glusterfs localhost:/conf "$GFS_CONF_MOUNT"
        fi
        if mountpoint -q "$GFS_FLOW_MOUNT"; then
                echo "volume flow already mounted"
        else
                echo "mounting volume flow"
                mount -t glusterfs localhost:/flow "$GFS_FLOW_MOUNT"
        fi

        # change the ownership (for IPFIXcol running as a $USER)
        declare -r GROUP="$(id -gn "$USER")"
        chown "${USER}:${GROUP}" "$GFS_CONF_MOUNT" "$GFS_FLOW_MOUNT"
}


################################################################################
# setup IPFIXcol functions
################################################################################
ipfixcol() {
        ssh_exec ipfixcol1_all "${ALL_NODES[@]}"
        ssh_exec ipfixcol2_one "${ALL_NODES[1]}"

        echo
        echo "Don't forget to alter/rewiev autogenerated configuration files" \
             "in \"${GFS_CONF_MOUNT}/ipfixcol/\"!"
}

ipfixcol1_all() {
        declare -r GITHUB_URL="${GITHUB_BASE_URL}/ipfixcol/ocf/"
        declare -r RA_PATH="/usr/lib/ocf/resource.d/"
        declare -r RA_PROVIDER="cesnet"
        declare -r RA_NAME="ipfixcol"

        # download and install OCF resource agent
        mkdir -p "${RA_PATH}/${RA_PROVIDER}/"

        echo "Downloading OCF resource agent"
        curl -sS "${GITHUB_URL}/${RA_NAME}" \
                >"${RA_PATH}/${RA_PROVIDER}/${RA_NAME}"
        chmod +x "${RA_PATH}/${RA_PROVIDER}/${RA_NAME}"
}

ipfixcol2_one() {
        declare -r PROXY_CONF="${GFS_CONF_MOUNT}/ipfixcol/startup-proxy.xml"
        declare -r SUB_CONF="${GFS_CONF_MOUNT}/ipfixcol/startup-subcollector.xml"

        # create directory for configuration files
        mkdir -p "$(dirname "$PROXY_CONF")"

        # generate list of destinations for the proxy startup XML configuration
        # file
        local XML_DESTINATION
        local SUB
        for SUB in "${SUB_NODES[@]}"; do
                XML_DESTINATION="${XML_DESTINATION}<destination><ip>${SUB}</ip></destination>"
        done

        echo "Generating proxy startup configuration file \"${PROXY_CONF}\""
        xmllint --format --output "$PROXY_CONF" - << END
<?xml version="1.0" encoding="UTF-8"?>
<ipfix xmlns="urn:ietf:params:xml:ns:yang:ietf-ipfix-psamp">

        <collectingProcess>
                <name>UDP-CPG collector</name>
                <udp-cpgCollector>
                        <name>Listening port 4739</name>
                        <localPort>4739</localPort>

                        <templateLifeTime>1800</templateLifeTime>
                        <optionsTemplateLifeTime>1800</optionsTemplateLifeTime>

                        <CPGName>ipfixcol</CPGName>

                </udp-cpgCollector>
                <exportingProcess>Forward UDP</exportingProcess>
        </collectingProcess>

        <exportingProcess>
                <name>Forward UDP</name>
                <destination>
                        <name>Forward flows to collectors</name>
                        <fileWriter>
                                <fileFormat>forwarding</fileFormat>
                                <distribution>RoundRobin</distribution>
                                <defaultPort>4741</defaultPort>
                                ${XML_DESTINATION}
                        </fileWriter>
                </destination>

                <singleManager>yes</singleManager>
        </exportingProcess>
</ipfix>
END

        echo "Generating subcollector startup configuration file \"$SUB_CONF\""
        xmllint --format --output "$SUB_CONF" - << END
<?xml version="1.0" encoding="UTF-8"?>
<ipfix xmlns="urn:ietf:params:xml:ns:yang:ietf-ipfix-psamp">

        <collectingProcess>
                <name>TCP collector</name>
                <tcpCollector>
                        <name>Listening port 4741</name>
                        <localPort>4741</localPort>
                </tcpCollector>
                <exportingProcess>Store flows</exportingProcess>
        </collectingProcess>

        <exportingProcess>
                <name>Store flows</name>
                <destination>
                        <name>Storage</name>
                        <fileWriter>
                                <fileFormat>lnfstore</fileFormat>
                                <profiles>no</profiles>
                                <storagePath>${GFS_FLOW_MOUNT}/%h/</storagePath>
                                <identificatorField>securitycloud</identificatorField>
                                <compress>yes</compress>
                                <dumpInterval>
                                        <timeWindow>300</timeWindow>
                                        <align>yes</align>
                                </dumpInterval>
                        </fileWriter>
                </destination>

                <singleManager>yes</singleManager>
        </exportingProcess>
</ipfix>
END
}


################################################################################
# setup fdistdump functions
################################################################################
fdistdump() {
        ssh_exec fdistdump1_all "${ALL_NODES[@]}"
}

fdistdump1_all() {
        declare -r GITHUB_URL="${GITHUB_BASE_URL}/fdistdump/"
        declare -r NAME="fdistdump-ha"
        declare -r DOWNLOAD_PATH="/usr/bin"

        # download and install HA launcher
        echo "Downloading HA launcher"
        curl -sS "${GITHUB_URL}/${NAME}" >"${DOWNLOAD_PATH}/${NAME}"
        chmod +x "${DOWNLOAD_PATH}/${NAME}"
}


################################################################################
# setup corosync/pacemaker functions
################################################################################
stack() {
        ssh_exec stack1_all "${ALL_NODES[@]}"
        ssh_exec stack2_one "${ALL_NODES[0]}"
}

stack1_all() {
        # pcs is made for RHEL and requires "/var/log/cluster/" for Corosync
        # logfiles, but debian uses "/var/log/corosync/"
        declare -r RHEL_LOGDIR="/var/log/cluster/"
        declare -r DEB_LOGDIR="/var/log/corosync/"
        if [ ! -e "$RHEL_LOGDIR" ]; then
                if [ -e "$DEB_LOGDIR" -a -d "$DEB_LOGDIR" ]; then
                        ln -s "$DEB_LOGDIR" "${RHEL_LOGDIR%/}"
                else
                        error "missing log directory ($RHEL_LOGDIR or $DEB_LOGDIR)"
                        return 1
                fi
        fi

        # setup corosync localy for all nodes (we are not using pcsd)
        pcs cluster setup --local --name "security_cloud" "${ALL_NODES[@]}" \
                --force

        # start and enable corosync, start pacemaker (as a precaution we want to
        # prevent pacemaker from starting immediately on our nodes after reboot)
        if [ -f /.dockerenv ]; then
                # inside docker container
                /etc/init.d/corosync start
                /etc/init.d/pacemaker start
        else
                pcs cluster start
                systemctl enable corosync.service
        fi

        # verify
        corosync-cpgtool >/dev/null
        sleep 5 # pacemaker needs some rest before it is ready for action

        # delete "successor" node property (attribute) everywhere
        crm_attribute "--node=$(uname -n)" "--name=successor" --delete
        # set "successor" node property (attribute) appropriately
        declare -ir CNT=${#SUB_NODES[@]}
        for ((I=0; I<CNT; I++)); do
                for FQDN in $(hostname -A); do
                        # am I among subcollectors?
                        if [ "${SUB_NODES[$I],,}" = "${FQDN,,}" ]; then
                                declare -r PROP="successor=$(((I+1)%CNT+1))"
                                echo setting property \"${PROP%%=*}\" to \
                                     \"${PROP#*=}\"
                                crm_attribute --node="$(uname -n)" \
                                        --name="successor" \
                                        --update="${PROP#*=}"
                        fi
                done
        done
}

stack2_one() {
        # properties (attributes) ##############################################
        # stonith-enabled: should failed nodes and nodes with resources that
        #                  can’t be stopped be shot?
        # flow-primary-brick: store info about GlusterFS for fdistdump-ha
        # flow-backup-brick: store info about GlusterFS for fdistdump-ha
        declare -ar PROPERTIES=(
                "stonith-enabled=false"
                "flow-primary-brick=$GFS_FLOW_PRIMARY_BRICK"
                "flow-backup-brick=$GFS_FLOW_BACKUP_BRICK"
                )
        local PROP
        for PROP in "${PROPERTIES[@]}"; do
                echo setting property \"${PROP%%=*}\" to \"${PROP#*=}\"
                crm_attribute  --name="${PROP%%=*}" --update="${PROP#*=}"
        done


        # gluster deamon #######################################################
        # create a primitive resource for managing gluster daemon
        pcs_resource_create "gluster-daemon" "ocf:glusterfs:glusterd" \
                op \
                monitor "interval=20s"
        # create a clone with instance on every node
        pcs_resource_clone  "gluster-daemon" "interleave=true"


        # gluster conf #########################################################
        # create a primitive resource for mounting gluster volume "conf"
        pcs_resource_create "gluster-conf-mount" "ocf:heartbeat:Filesystem" \
                "device=localhost:/conf" "directory=$GFS_CONF_MOUNT" \
                "fstype=glusterfs" \
                op \
                start "timeout=60" \
                stop "timeout=60" \
                monitor "interval=20" "OCF_CHECK_LEVEL=0" \
                monitor "interval=60" "timeout=60" "OCF_CHECK_LEVEL=20"
        # create a clone with instance on every node
        pcs_resource_clone "gluster-conf-mount" "interleave=true"
        # make sure gluster daemon is started during startup and when running
        pcs_constraint_order "gluster-daemon-clone" "gluster-conf-mount-clone" \
                "mandatory"


        # gluster flow #########################################################
        # create a primitive resource for mounting gluster volume "flow"
        pcs_resource_create "gluster-flow-mount" "ocf:heartbeat:Filesystem" \
                "device=localhost:/flow" "directory=$GFS_FLOW_MOUNT" \
                "fstype=glusterfs" \
                op \
                start "timeout=60" \
                stop "timeout=60" \
                monitor "interval=20" "OCF_CHECK_LEVEL=0" \
                monitor "interval=60" "timeout=60" "OCF_CHECK_LEVEL=20"
        # create a clone with instance on every node
        pcs_resource_clone "gluster-flow-mount" "interleave=true"
        # make sure gluster daemon is started during startup and when running
        pcs_constraint_order "gluster-daemon-clone" "gluster-flow-mount-clone" \
                "mandatory"


        # IPFIXcol proxy #######################################################
        # NOTE: if we would create a clone with instance on utmost two nodes
        # (clone-max=2) we would save some resources, but we would run
        # into problem described here:
        # http://lists.clusterlabs.org/pipermail/users/2017-April/005560.html

        # create a primitive resource for IPFIXcol in a proxy role
        pcs_resource_create "ipfixcol-proxy" "ocf:cesnet:ipfixcol" \
                "role=proxy" \
                "startup_conf=$GFS_CONF_MOUNT/ipfixcol/startup-proxy.xml" \
                op \
                monitor "interval=20" \
                meta "migration-threshold=1" "failure-timeout=600"
        # create a clone with instance on utmost two nodes
        pcs_resource_clone "ipfixcol-proxy" "interleave=true"
        # make sure gluster conf volume is mounted during startup
        pcs_constraint_order "gluster-conf-mount-clone" "ipfixcol-proxy-clone" \
                "optional"
        # prefer to run on dedicated proxy nodes (nodes without defined
        # "successor" property)
        pcs_constraint_location "ipfixcol-proxy-clone" \
                100 not_defined "successor"


        # IPFIXcol subcollector ################################################
        # create a primitive resource for IPFIXcol in a subcollector role
        pcs_resource_create "ipfixcol-subcollector" "ocf:cesnet:ipfixcol" \
                "role=subcollector" \
                "startup_conf=$GFS_CONF_MOUNT/ipfixcol/startup-subcollector.xml" \
                op \
                monitor "interval=20"
        # create a clone with instance on every node
        pcs_resource_clone "ipfixcol-subcollector" "interleave=true"
        # make sure gluster conf volume is mounted during startup
        pcs_constraint_order "gluster-conf-mount-clone" \
                "ipfixcol-subcollector-clone" "optional"
        # make sure gluster flow volume is mounted during startup and when
        # running
        pcs_constraint_order "gluster-flow-mount-clone" \
                "ipfixcol-subcollector-clone" "mandatory"
        # never run on dedicated proxy nodes (nodes without defined "successor"
        # property)
        pcs_constraint_location "ipfixcol-subcollector-clone" \
                "-INFINITY" not_defined "successor"


        # virtual (floating) IP address ########################################
        # create a primitive resource
        pcs_resource_create "virtual-ip" "ocf:heartbeat:IPaddr2" \
                "ip=$VIP_ADDRESS" "cidr_netmask=$VIP_PREFIX" \
                "nic=$VIP_INTERFACE" \
                op \
                monitor "interval=20" \
                meta "resource-stickiness=1"
        # make sure virtual IP runs on the same node where the cluster has
        # determined IPFIXcol proxy should run
        pcs_constraint_colocation "virtual-ip" "ipfixcol-proxy-clone" 1000
}

pcs_resource_create() {
        # pcs resource create <resource id> <type> [resource options] [op ...]
        #       [meta ...]
        declare -r RES_ID="$1"
        declare -r RES_TYPE="$2"
        shift 2
        #declare -r WAIT="--wait"  # wait for resource to start?

        if ! pcs resource show "$RES_ID" >/dev/null; then
                echo creating a resource "$RES_ID"
                pcs resource create "$RES_ID" "$RES_TYPE" "$@" $WAIT
        fi
}

pcs_resource_clone() {
        # pcs resource clone <resource id> [clone options]
        declare -r RES_ID="$1"
        shift 1
        #declare -r WAIT="--wait"  # wait for resource to start?

        if ! pcs resource show "$RES_ID-clone" >/dev/null; then
                echo creating a clone of the resource "$RES_ID"
                pcs resource clone "$RES_ID" "$@" $WAIT
        fi
}

pcs_constraint_location() {
        # pcs constraint location <resource id> rule [...] [score=<score>]
        #        <expression>
        declare -r RES_ID="$1"
        declare -r SCORE="$2"
        shift 2

        if ! pcs constraint location show --full \
                | grep "id:location-$RES_ID-rule-expr" \
                >/dev/null
        then
                echo creating a location constraint for the resource "$RES_ID"
                pcs constraint location "$RES_ID" rule "score=$SCORE" "$@"
        fi
}

pcs_constraint_order() {
        # pcs constraint order [action] <resource id> then [action]
        #       <resource id> [options]
        declare -r RES_ID_FIRST="$1"
        declare -r RES_ID_THEN="$2"
        declare -r KIND="${3,,}"  # to lowercase
        shift 3

        if ! pcs constraint order show --full \
                | grep "id:order-$RES_ID_FIRST-$RES_ID_THEN-${KIND^}" \
                >/dev/null
        then
                echo creating a resource ordering constraint \""$RES_ID_FIRST" \
                     before "$RES_ID_THEN"\"
                pcs constraint order "$RES_ID_FIRST" "then" "$RES_ID_THEN" \
                        "kind=${KIND^}" >/dev/null
        fi
}

pcs_constraint_colocation() {
        # pcs constraint colocation add <source resource id> with
        #       <target resource id> [score] [options] [id=constraint-id]
        #
        # Request RES_ID_SRC to run on the same node where pacemaker has
        # determined RES_ID_DST should run.
        # Include RES_ID_SRC's preferences when deciding where to put
        # RES_ID_DST.
        # If RES_ID_DST cannot run anywhere, RES_ID_SRC can't run either.
        # If RES_ID_SRC cannot run anywhere, RES_ID_DST will be unaffected.

        declare -r RES_ID_SRC="$1"
        declare -r RES_ID_DST="$2"
        declare -r SCORE="$3"
        shift 3

        if ! pcs constraint colocation show --full \
                | grep "id:colocation-$RES_ID_SRC-$RES_ID_DST-$SCORE" \
                >/dev/null
        then
                echo creating a colocation constraint \""$RES_ID_SRC" where \
                        "$RES_ID_DST"\"
                pcs constraint colocation add "$RES_ID_SRC" with "$RES_ID_DST" \
                        "$SCORE" >/dev/null
        fi
}


################################################################################
# call main
main "$@"


################################################################################
# delete all resources
# IDS=$(pcs resource --full \
#         | grep "\(Resource\)\|\(Clone\):" \
#         | sed "s/[^:]*: \([^ ]*\).*/\1/")
# for ID in ${IDS}; do
#         pcs resource delete "$ID"
# done

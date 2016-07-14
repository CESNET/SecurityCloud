#!/usr/bin/env bash
#author: Jan Wrona, wrona@cesnet.cz

#TODO: gluster force?
#      don't download files

################################################################################
#common functions
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
        echo -e "\tsetup_gluster     setup GlusterFS file system"
}

error() {
        echo -e "Error on node $(hostname): $1"
        [ -z "$2" ] || echo -e "\tcommand: $2"
        [ -z "$3" ] || echo -e "\toutput: $3"
        [ -z "$4" ] || echo -e "\treturn code: $4"
}

parse_config() {
        local KEY VALUE IFS="="

        while read -r KEY VALUE
        do
                #strip whitespaces around the KEY
                KEY="$(echo "${KEY}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

                case "${KEY}" in
                        #definition of nodes
                        "node_proxy")
                                PRO_NODES[${#PRO_NODES[*]}]="${VALUE}"
                                ALL_NODES[${#ALL_NODES[*]}]="${VALUE}"
                                ;;
                        "node_subcollector")
                                SUB_NODES[${#SUB_NODES[*]}]="${VALUE}"
                                ALL_NODES[${#ALL_NODES[*]}]="${VALUE}"
                                ;;

                        #GlusterFS options
                        "gfs_conf_brick") GFS_CONF_BRICK="${VALUE}";;
                        "gfs_flow_primary_brick") GFS_FLOW_PRIMARY_BRICK="${VALUE}";;
                        "gfs_flow_backup_brick") GFS_FLOW_BACKUP_BRICK="${VALUE}";;
                        "gfs_conf_mount") GFS_CONF_MOUNT="${VALUE}";;
                        "gfs_flow_mount") GFS_FLOW_MOUNT="${VALUE}";;
                esac
        done < <(grep "^[^=]*=" "$1") #process substitution magic
}

ssh_exec() {
        local NODES=$1 CONF_NAME=$(basename "${CONF_FILE}")
        shift

        for NODE in ${NODES}
        do
                ssh "${NODE}" "/tmp/${0}" $* -c "/tmp/${CONF_NAME}" -s || return $?
        done
}


################################################################################
#health checking functions

check() {
        echo "################################################################################"
        echo "CHECK"
        echo

        ssh_exec "${ALL_NODES[*]}" check_network || return $?
        ssh_exec "${ALL_NODES[*]}" check_programs || return $?
        ssh_exec "${ALL_NODES[*]}" check_libraries || return $?

        echo
        echo "It seems that everyting went OK"
        echo "################################################################################"
}

check_network() {
        local OUT RC NODE

        for NODE in ${ALL_NODES[*]}
        do
                #test getnet ahosts
                OUT="$(getent ahosts "${NODE}" 2>&1)"
                RC=$?
                if [ $RC -ne 0 ]
                then
                        error "getent test" "getent ahosts ${NODE}" "${OUT}" $RC
                        return $RC
                fi

                #test ping
                OUT="$(ping -c 1 "${NODE}" 2>&1)"
                RC=$?
                if [ $RC -ne 0 ]
                then
                        error "ping test" "ping -c 1 ${NODE}" "${OUT}" $RC
                        return $RC
                fi

                #test SSH
                OUT="$(ssh "${NODE}" true 2>&1)"
                RC=$?
                if [ $RC -ne 0 ]
                then
                        error "SSH test (not working SSH to ${NODE})" "ssh ${NODE} true" "${OUT}" $RC
                        return $RC
                fi
        done
}

check_programs() {
        local OUT RC PROG

        for PROG in ${PROGRAMS[*]}
        do
                #test presence of the program
                OUT="$(command -v "${PROG}" 2>&1)"
                RC=$?
                if [ $RC -ne 0 ]
                then
                        error "program test (\"${PROG}\" is not installed)" "command -v ${PROG}" "${OUT}" $RC
                        return $RC
                fi
        done
}

check_libraries() {
        local OUT RC LIB

        for LIB in ${LIBRARIES[*]}
        do
                #test presence of the library
                OUT="$(ldconfig -p | grep "${LIB}\." 2>&1)"
                RC=$?
                if [ $RC -ne 0 ]
                then
                        error "library test (\"${LIB}\" is not installed)" "ldconfig -p | grep \"${LIB}\.\"" "${OUT}" $RC
                        return $RC
                fi
        done
}


################################################################################
#setup GlusterFS functions

setup_gluster() {
        echo "################################################################################"
        echo "SETING UP GLUSTERFS"
        echo

        ssh_exec "${ALL_NODES[*]}" setup_gluster1_all || return $?
        ssh_exec "${ALL_NODES[0]}" setup_gluster2_one || return $?
        ssh_exec "${ALL_NODES[*]}" setup_gluster3_all || return $?

        echo
        echo "It seems that everyting went OK"
        echo "################################################################################"
}

setup_gluster1_all() {
        local OUT RC

        #create directories for bricks
        mkdir -p "${GFS_CONF_BRICK}" "${GFS_FLOW_PRIMARY_BRICK}" "${GFS_FLOW_BACKUP_BRICK}" || return $?
        #create directories for mount points
        mkdir -p "${GFS_CONF_MOUNT}" "${GFS_FLOW_MOUNT}" || return $?

        #check if glusterd is running
        OUT="$(pgrep glusterd 2>&1)"
        RC=$?
        if [ $RC -ne 0 ]
        then
                error "GlusterFS daemon is not running" "pgrep glusterd" "${OUT}" $RC
                return $RC
        fi
        OUT="$(netstat -tavn | grep "2400[7|8]" 2>&1)"
        RC=$?
        if [ $RC -ne 0 ]
        then
                error "GlusterFS daemon is not running" "netstat -tavn | grep \"2400[7|8]\"" "${OUT}" $RC
                return $RC
        fi

        #download and install custom filter
        local GFS_VERSION="$(gluster --version | head -1 | cut -d" " -f 2)" || return $?
        local GFS_PATH="$(find /usr/ -type d -path "/usr/lib*/glusterfs/${GFS_VERSION}")" || return $?
        mkdir -p "${GFS_PATH}/filter/"
        wget -O "${GFS_PATH}/filter/filter.py" "https://raw.githubusercontent.com/CESNET/SecurityCloud/master/gluster/filter.py" &> /dev/null || return $?
        chmod +x "${GFS_PATH}/filter/filter.py"
}

setup_gluster2_one() {
        local NODE CONF_BRICKS FLOW_BRICKS

        #create trusted pool
        for NODE in ${ALL_NODES[*]}
        do
                gluster peer probe "${NODE}" || return $?
                CONF_BRICKS="${CONF_BRICKS}${NODE}:${GFS_CONF_BRICK} "
        done


        #create configuration volume "conf"
        if gluster volume info conf &> /dev/null; then
                echo "volume conf already exists"
        else
                echo "creating volume conf"
                gluster volume create conf replica 4 ${CONF_BRICKS} force || return $?

                #disable NFS
                gluster volume set conf nfs.disable true || return $?
                #set timetou from 42 to 10 seconds for faster reactions to failures
                gluster volume set conf network.ping-timeout 10 || return $?
        fi
        #start configuration volume "conf"
        if gluster volume status conf &> /dev/null; then
                echo "volume conf already started"
        else
                echo "starting volume conf"
                gluster volume start conf || return $?
        fi


        #create bricks specification for data volume "flow" (ring topology)
        local CNT=${#SUB_NODES[*]}
        for ((I=0; I<CNT; I++))
        do
                FLOW_BRICKS="${FLOW_BRICKS}${SUB_NODES[${I}]}:${GFS_FLOW_PRIMARY_BRICK} ${SUB_NODES[$(((I+1)%CNT))]}:${GFS_FLOW_BACKUP_BRICK} "
        done
        #create data volume "flow"
        if gluster volume info flow &> /dev/null; then
                echo "volume flow already exists"
        else
                echo "creating volume flow"
                gluster volume create flow replica 2 ${FLOW_BRICKS} force || return $?

                #disable NFS
                gluster volume set flow nfs.disable true || return $?
                #set timetou from 42 to 10 seconds for faster reactions to failures
                gluster volume set flow network.ping-timeout 10 || return $?
                #enable NUFA
                gluster volume set flow cluster.nufa enable
        fi
        #start data volume "flow"
        if gluster volume status flow &> /dev/null; then
                echo "volume flow already started"
        else
                echo "starting volume flow"
                gluster volume start flow || return $?
        fi
}

setup_gluster3_all() {
        #mount configuration volume "conf"
        if mountpoint -q "${GFS_CONF_MOUNT}"; then
                echo "volume conf already mounted"
        else
                echo "mounting volume conf"
                mount -t glusterfs localhost:/conf "${GFS_CONF_MOUNT}"
        fi

        #mount data volume "flow"
        if mountpoint -q "${GFS_FLOW_MOUNT}"; then
                echo "volume flow already mounted"
        else
                echo "mounting volume flow"
                mount -t glusterfs localhost:/flow "${GFS_FLOW_MOUNT}"
        fi
}


################################################################################
#initialization, default argument values
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONF_FILE="${DIR}/install.conf"
PROGRAMS=(libnf-info ipfixcol fdistdump corosync pacemakerd pcs glusterd gluster)
LIBRARIES=(libnf libcpg)

#check argument count
if [ $# -lt 1 ]; then
        error "bad arguments"
        echo
        print_usage
        exit 1
fi

#parse arguments
while [ $# -gt 0 ]
do
        case "${1}" in
                #arguments
                "-c") #config file
                        shift
                        CONF_FILE="$1"
                        ;;
                "-h") #help
                        print_help
                        exit 0
                        ;;

                #internal use only
                "-s") #running over SSH
                        shift
                        SSH=1
                        ;;

                #commands
                *) #anything else
                        COMMAND=${COMMAND}"${1} "
                        ;;
        esac
        shift
done

#check configuration file existence
if [ ! -f "${CONF_FILE}" ]; then
        echo "Error: cannot open configuration file \"${CONF_FILE}\""
        exit 1
fi

#parse configuration file
parse_config "${CONF_FILE}"

#check nodes definition
if [ "${#ALL_NODES[*]}" -lt 2 ]; then
        error "we need at least two nodes"
        exit 1
fi
if [ "${#SUB_NODES[*]}" -lt 1 ]; then
        error "we need at least one subcollector node"
        exit 1
fi

#replicate this script and the configuration file to all nodes
if [ -z "${SSH}" ]; then
        check_network || exit $?

        for NODE in ${ALL_NODES[*]}
        do
                scp "${0}" "${CONF_FILE}" "${NODE}:/tmp/" &> /dev/null &
        done
        wait
fi

#execute supplied command (it is supposed to be a function)
${COMMAND}

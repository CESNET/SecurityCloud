#!/usr/bin/env bash

#author: Jan Wrona, wrona@cesnet.cz

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


#TODO: gluster force?
#      don't download files
#      configuration variable prefix


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
        echo -e "\tglusterfs         setup GlusterFS file system"
        echo -e "\tipfixcol          setup IPFIXcol framework"
        echo -e "\tfdistdump         setup fdistdump query tool"
        echo -e "\tstack             setup Corosync and Pacemaker stack"
}

warning() {
        echo -e "Warning on node $(hostname): $1" >&2
        [ -z "$2" ] || echo -e "\tcommand: $2" >&2
        [ -z "$3" ] || echo -e "\toutput: $3" >&2
        [ -z "$4" ] || echo -e "\treturn code: $4" >&2
}

error() {
        echo -e "Error on node $(hostname): $1" >&2
        [ -z "$2" ] || echo -e "\tcommand: $2" >&2
        [ -z "$3" ] || echo -e "\toutput: $3" >&2
        [ -z "$4" ] || echo -e "\treturn code: $4" >&2
}

parse_config() {
        local KEY VALUE IFS="="

        while read -r KEY VALUE
        do
                #strip whitespaces around the KEY and VALUE
                KEY="$(echo "${KEY}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                VALUE="$(echo "${VALUE}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

                case "${KEY}" in
                        #definition of nodes
                        "node_proxy") PRO_NODES[${#PRO_NODES[*]}]="${VALUE}" ;;
                        "node_subcollector") SUB_NODES[${#SUB_NODES[*]}]="${VALUE}" ;;

                        #GlusterFS options
                        "gfs_conf_brick") GFS_CONF_BRICK="${VALUE}" ;;
                        "gfs_flow_primary_brick") GFS_FLOW_PRIMARY_BRICK="${VALUE}" ;;
                        "gfs_flow_backup_brick") GFS_FLOW_BACKUP_BRICK="${VALUE}" ;;
                        "gfs_conf_mount") GFS_CONF_MOUNT="${VALUE}" ;;
                        "gfs_flow_mount") GFS_FLOW_MOUNT="${VALUE}" ;;

                        #other options
                        "virtual_ip") VIRTUAL_IP="${VALUE}" ;;
                esac
        done < <(grep "^[^=]*=" "$1") #process substitution magic

        ALL_NODES=( ${SUB_NODES[*]} ${PRO_NODES[*]} )
}

check_config() {
        #check nodes definition
        if [ "${#ALL_NODES[*]}" -lt 2 ]; then
                error "we need at least two nodes"
                return 1
        fi
        if [ "${#SUB_NODES[*]}" -lt 1 ]; then
                error "we need at least one subcollector node"
                return 1
        fi

        #check GlusterFS options
        #TODO

        #check other options
        #TODO
}

ssh_exec() {
        if [ -n "${SSH}" ]; then
                error "recursive SSH exec"
                exit 1
        fi

        local NODES=$1 BINARY="$(basename "$0")" CONF_NAME="$(basename "${CONF_FILE}")"
        shift

        for NODE in ${NODES}
        do
                echo "Connecting to ${NODE}."
                ssh -o "StrictHostKeyChecking no" -t "${NODE}" "/tmp/${BINARY}" $* -c "/tmp/${CONF_NAME}" -s || return $?
                echo
        done
}


################################################################################
#health checking functions

check() {
        ssh_exec "${ALL_NODES[*]}" check_network || return $?
        ssh_exec "${ALL_NODES[*]}" check_programs || return $?
        ssh_exec "${ALL_NODES[*]}" check_libraries || return $?
}

check_network() {
        local OUT RC NODE

        for NODE in ${ALL_NODES[*]}
        do
                #test getnet ahosts
                #TODO: solve problem with node name resolved into localhost IP
                OUT="$(getent ahosts "${NODE}" 2>&1)"
                RC=$?
                if [ $RC -ne 0 ]; then
                        error "unable to resolve \"${NODE}\"" "getent ahosts ${NODE}" "${OUT}" $RC
                        return $RC
                fi
                if echo "${OUT}" | grep "^\(127\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+[[:space:]]\)\|\(::1[[:space:]]\)" &> /dev/null; then
                        error "${NODE} is mapped to localhost IP address" "getent ahosts ${NODE}"
                        return 1
                fi

                #test ping
                OUT="$(ping -c 1 "${NODE}" 2>&1)"
                RC=$?
                if [ $RC -ne 0 ]; then
                        error "unable to ping ${NODE}" "ping -c 1 ${NODE}" "${OUT}" $RC
                        return $RC
                fi

                #test SSH
                OUT="$(ssh -o "StrictHostKeyChecking no" "${NODE}" true 2>&1)"
                RC=$?
                if [ $RC -ne 0 ]; then
                        error "unable to SSH to ${NODE}" "ssh -o \"StrictHostKeyChecking no\" ${NODE} true" "${OUT}" $RC
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
                        error "program \"${PROG}\" is not installed" "command -v ${PROG}" "${OUT}" $RC
                        return $RC
                fi
        done

        #user existence test
        if ! getent passwd "${USER}" >/dev/null; then
                error "user \"${USER}\" doesn't exist" "getent passwd ${USER}"
                return 1
        fi

        #group existence test
        if ! getent group "${GROUP}" >/dev/null; then
                error "group \"${GROUP}\" doesn't exist" "getent group ${GROUP}"
                return 1
        fi
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
                        error "library \"${LIB}\" is not installed" "ldconfig -p | grep \"${LIB}\.\"" "${OUT}" $RC
                        return $RC
                fi
        done
}


################################################################################
#setup GlusterFS functions

glusterfs() {
        ssh_exec "${ALL_NODES[*]}" gluster1_all || return $?
        ssh_exec "${ALL_NODES[0]}" gluster2_one || return $?
        ssh_exec "${ALL_NODES[*]}" gluster3_all || return $?
}

gluster1_all() {
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
        echo "Downloading custom GlusterFS filter"
        local GFS_VERSION="$(gluster --version | head -1 | cut -d" " -f 2)" || return $?
        local GFS_PATH="$(find /usr/ -type d -path "/usr/lib*/glusterfs/${GFS_VERSION}")" || return $?
        mkdir -p "${GFS_PATH}/filter/"
        wget -nv -O "${GFS_PATH}/filter/filter.py" "https://raw.githubusercontent.com/CESNET/SecurityCloud/master/gluster/filter.py" || return $?
        chmod +x "${GFS_PATH}/filter/filter.py"
}

gluster2_one() {
        local NODE CONF_BRICKS FLOW_BRICKS

        #create trusted pool
        for NODE in ${ALL_NODES[*]}
        do
                gluster peer probe "${NODE}" || return $?
                sleep 1

                #wait for desired peer state
                while gluster peer status | grep -i "state:" | grep -iv "peer in cluster" &>/dev/null
                do
                        echo "waiting for \"${NODE}\" to get into the \"Peer in Cluster\" state"
                        sleep 1
                done

                CONF_BRICKS="${CONF_BRICKS}${NODE}:${GFS_CONF_BRICK} "
        done

        #create configuration volume "conf"
        if gluster volume info conf &> /dev/null; then
                echo "volume conf already exists"
        else
                echo "creating volume conf"
                gluster volume create conf replica "${#ALL_NODES[*]}" ${CONF_BRICKS} force || return $?
                sleep 1

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

gluster3_all() {
        #mount configuration volume "conf"
        if mountpoint -q "${GFS_CONF_MOUNT}"; then
                echo "volume conf already mounted"
        else
                echo "mounting volume conf"
                mount -t glusterfs localhost:/conf "${GFS_CONF_MOUNT}" || return $?
        fi
        #change owner so IPFIXcol running under $USER can write there
        chown "${USER}":"${GROUP}" "${GFS_CONF_MOUNT}"

        #mount data volume "flow"
        if mountpoint -q "${GFS_FLOW_MOUNT}"; then
                echo "volume flow already mounted"
        else
                echo "mounting volume flow"
                mount -t glusterfs localhost:/flow "${GFS_FLOW_MOUNT}" || return $?
        fi
        #change owner so IPFIXcol running under $USER can write there
        chown "${USER}":"${GROUP}" "${GFS_FLOW_MOUNT}"
}


################################################################################
#setup IPFIXcol functions

ipfixcol() {
        ssh_exec "${ALL_NODES[*]}" ipfixcol1_all || return $?
        ssh_exec "${ALL_NODES[1]}" ipfixcol2_one || return $?

        echo
        echo "Don't forget to alter/rewiev autogenerated configuration files in \"${GFS_CONF_MOUNT}/ipfixcol/\"!"
}

ipfixcol1_all() {
        local OCF_PATH="/usr/lib/ocf/resource.d/"

        #download and install OCF resource agent
        echo "Downloading OCF resource agent"
        mkdir -p "${OCF_PATH}/cesnet/"
        wget -nv -O "${OCF_PATH}/cesnet/ipfixcol.sh" "https://raw.githubusercontent.com/CESNET/SecurityCloud/master/ipfixcol/ocf/ipfixcol.sh" || return $?
        wget -nv -O "${OCF_PATH}/cesnet/ipfixcol.metadata" "https://raw.githubusercontent.com/CESNET/SecurityCloud/master/ipfixcol/ocf/ipfixcol.metadata" || return $?
        chmod +x "${OCF_PATH}/cesnet/ipfixcol.sh"
}

ipfixcol2_one() {
        local PROXY_CONF="${GFS_CONF_MOUNT}/ipfixcol/startup-proxy.xml"
        local SUB_CONF="${GFS_CONF_MOUNT}/ipfixcol/startup-subcollector.xml"
        local XML_DESTINATION

        #create directory for configuration files
        mkdir -p "$(dirname "${PROXY_CONF}")" || return $?

        #generate list of destinations for the proxy startup XML configuration file
        for SUB in ${SUB_NODES[*]}
        do
                XML_DESTINATION="${XML_DESTINATION}<destination><ip>${SUB}</ip></destination>"
        done

        echo "Generating proxy startup configuration file \"${PROXY_CONF}\""
        xmllint --format --output "${PROXY_CONF}" - << END
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


        echo "Generating subcollector startup configuration file \"${SUB_CONF}\""
        xmllint --format --output "${SUB_CONF}" - << END
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
                                <prefix>nfcapd.</prefix>
                                <suffixMask>%Y%m%d%H%M%S</suffixMask>
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
#setup fdistdump functions

fdistdump() {
        ssh_exec "${ALL_NODES[*]}" fdistdump1_all || return $?
}

fdistdump1_all() {
        local PATHNAME="$(type -fp fdistdump)"
        local DIRNAME="$(dirname "${PATHNAME}")"

        #download and install HA launcher
        echo "Downloading HA launcher"
        wget -nv -O "${DIRNAME}/fdistdump-ha" "https://raw.githubusercontent.com/CESNET/SecurityCloud/master/fdistdump/fdistdump-ha" || return $?
        chmod +x "${DIRNAME}/fdistdump-ha"
}


################################################################################
#setup corosync/pacemaker functions

stack() {
        ssh_exec "${ALL_NODES[*]}" stack1_all || return $?
        ssh_exec "${ALL_NODES[0]}" stack2_one || return $?
}

stack1_all() {
        #pcs is made for RHEL and requires "/var/log/cluster/" for Corosync logfiles, but debian uses "/var/log/corosync/"
        local RHEL_LOGDIR="/var/log/cluster/" DEB_LOGDIR="/var/log/corosync/"
        if [ ! -e "${RHEL_LOGDIR}" ]; then
                if [ -e "${DEB_LOGDIR}" -a -d "${DEB_LOGDIR}" ]; then
                        ln -s "${DEB_LOGDIR}" "${RHEL_LOGDIR%/}"
                else
                        error "missing log directory (${RHEL_LOGDIR} or ${DEB_LOGDIR})"
                        exit 1
                fi
        fi

        #setup corosync localy for all nodes (we are not using pcsd), start and enable corosync and pacemaker
        pcs cluster setup --local --name "security_cloud" ${ALL_NODES[*]} --force || return $?
        pcs cluster start || return $?
        #pcs cluster enable || return $? #doesn't work on debian
        systemctl enable corosync.service || return $?
        #as a precaution we want to prevent pacemaker from starting immediately on our nodes
        #systemctl enable pacemaker.service || return $?

        #verify
        corosync-cpgtool > /dev/null || return $?
        sleep 5 #Pacemaker needs some rest before it is ready for action

        #delete "successor" node property (attribute) everywhere
        crm_attribute "--node=$(uname -n)" "--name=successor" --delete || return $?
        #set "successor" node property (attribute) appropriately
        local CNT=${#SUB_NODES[*]}
        for ((I=0; I<CNT; I++))
        do
                for FQDN in $(hostname -A)
                do
                        #am I amongst subcollectors?
                        if [ "${SUB_NODES[$I],,}" = "${FQDN,,}" ]; then
                                PROP="successor=$(((I+1)%CNT+1))"
                                echo "property \"${PROP%%=*}\": setting to \"${PROP#*=}\""
                                crm_attribute --node="$(uname -n)" --name="successor" --update="${PROP#*=}" || return $?
                        fi
                done
        done
}

stack2_one() {
        ################################################################################
        #properties (attributes)
        ################################################################################
        #stonith-enabled: Should failed nodes and nodes with resources that can’t be stopped be shot?)
        #flow-primary-brick: store info about GlusterFS for fdistdump-ha
        #flow-backup-brick: store info about GlusterFS for fdistdump-ha
        local PROPERTIES=(
                "stonith-enabled=false"
                "flow-primary-brick=${GFS_FLOW_PRIMARY_BRICK}"
                "flow-backup-brick=${GFS_FLOW_BACKUP_BRICK}"
                )
        for PROP in ${PROPERTIES[*]}
        do
                echo "property \"${PROP%%=*}\": setting to \"${PROP#*=}\""
                crm_attribute  --name="${PROP%%=*}" --update="${PROP#*=}" || return $?
        done


        ################################################################################
        #resources
        ################################################################################
        #create and clone resource for managing gluster daemon
        pcs_resource_create "gluster-daemon" "ocf:glusterfs:glusterd" op monitor "interval=20s" || return $?
        pcs_resource_clone  "gluster-daemon" "interleave=true" || return $?

        #create and clone resource for mounting gluster configuration volume "conf"
        pcs_resource_create "gluster-conf-mount" "ocf:heartbeat:Filesystem" \
                        "device=localhost:/conf" "directory=${GFS_CONF_MOUNT}" "fstype=glusterfs" \
                        op start "timeout=60" stop "timeout=60" monitor "interval=20" "OCF_CHECK_LEVEL=0" monitor "interval=60" "OCF_CHECK_LEVEL=20" || return $?
        pcs_resource_clone "gluster-conf-mount" "interleave=true" || return $?

        #create and clone resource for mounting gluster data volume "flow"
        pcs_resource_create "gluster-flow-mount" "ocf:heartbeat:Filesystem" \
                        "device=localhost:/flow" "directory=${GFS_FLOW_MOUNT}" "fstype=glusterfs" \
                        op start "timeout=60" stop "timeout=60" monitor "interval=20" "OCF_CHECK_LEVEL=0" monitor "interval=60" "OCF_CHECK_LEVEL=20" || return $?
        pcs_resource_clone "gluster-flow-mount" "interleave=true" || return $?

        #create and clone resource for IPFIXcol in role proxy
        pcs_resource_create "ipfixcol-proxy" "ocf:cesnet:ipfixcol.sh" \
                        "role=proxy" "startup_conf=${GFS_CONF_MOUNT}/ipfixcol/startup-proxy.xml" "verbosity=1" \
                        op monitor "interval=20" \
                        meta "migration-threshold=1" "failure-timeout=600" || return $?
        pcs_resource_clone "ipfixcol-proxy" "clone-max=2" "interleave=true" || return $?

        #create and clone resource for IPFIXcol in role subcollector
        pcs_resource_create "ipfixcol-subcollector" "ocf:cesnet:ipfixcol.sh" \
                        "role=subcollector" "startup_conf=${GFS_CONF_MOUNT}/ipfixcol/startup-subcollector.xml" "verbosity=1" \
                        op monitor "interval=20" || return $?
        pcs_resource_clone "ipfixcol-subcollector" "interleave=true" || return $?

        #create a resource for virtual IP address
        pcs_resource_create "virtual-ip" "ocf:heartbeat:IPaddr2" \
                        "ip=${VIRTUAL_IP}" \
                        op monitor "interval=20" \
                        meta "resource-stickiness=1" || return $?


        ################################################################################
        #constraints
        ################################################################################
        #IPFIXcol subcollector cannot run on dedicated proxy nodes (nodes without defined "successor" property)
        pcs_constraint_location "ipfixcol-subcollector-clone" "-INFINITY" not_defined "successor" || return $?
        #IPFIXcol proxy prefers dedicated proxy nodes (nodes without defined "successor" property)
        pcs_constraint_location "ipfixcol-proxy-clone" "100" not_defined "successor" || return $?

        #start gluster daemon clone before gluster conf can be mounted (interleaved)
        pcs_constraint_order "gluster-daemon-clone" "gluster-conf-mount-clone" "mandatory" || return $?
        #start gluster daemon clone before gluster flow can be mounted (interleaved)
        pcs_constraint_order "gluster-daemon-clone" "gluster-flow-mount-clone" "mandatory" || return $?

        #mount gluster conf volume before IPFIXcol proxy (optional, interleaved)
        pcs_constraint_order "gluster-conf-mount-clone" "ipfixcol-proxy-clone" "optional" || return $?

        #mount gluster conf volume before IPFIXcol subcollector (optional, interleaved)
        pcs_constraint_order "gluster-conf-mount-clone" "ipfixcol-subcollector-clone" "optional" || return $?
        #mount gluster flow volume before IPFIXcol subcollector (interleaved)
        pcs_constraint_order "gluster-flow-mount-clone" "ipfixcol-subcollector-clone" "mandatory" || return $?

        #virtual IP
        pcs_constraint_colocation "virtual-ip" "ipfixcol-proxy-clone" "INFINITY" || return $?
}

pcs_resource_create() {
        #pcs resource create <resource id> <type> [resource options] [op ...] [meta ...]
        RES_ID="$1"
        RES_TYPE="$2"
        shift 2

        if pcs resource show "${RES_ID}" &> /dev/null; then
                echo "resource ${RES_ID}: already exists, skipping"
                return
        fi

        echo "resource ${RES_ID}: creating"
        #pcs resource create "${RES_ID}" "${RES_TYPE}" $* --wait || return $?
        pcs resource create "${RES_ID}" "${RES_TYPE}" $* || return $?
}

pcs_resource_clone() {
        #pcs resource clone <resource id> [clone options]
        RES_ID="$1"
        shift

        if pcs resource show "${RES_ID}-clone" &> /dev/null; then
                echo "clone of the ${RES_ID}: already exists, skipping"
                return
        fi

        echo "clone of the ${RES_ID}: creating"
        #pcs resource clone "${RES_ID}" $* --wait || return $?
        pcs resource clone "${RES_ID}" $* || return $?
}

pcs_constraint_location() {
        #pcs constraint location <resource id> rule [...] [score=<score>] <expression>
        RES_ID="$1"
        SCORE="$2"
        shift 2

        if pcs constraint location show --full | grep "id:location-${RES_ID}-rule-expr" &> /dev/null; then
                echo "location constraint for ${RES_ID}: already exists, skipping"
                return
        fi

        echo "location constraint for ${RES_ID}: setting up"
        pcs constraint location "${RES_ID}" rule "score=${SCORE}" $* || return $?
}

pcs_constraint_order() {
        #pcs constraint order [action] <resource id> then [action] <resource id> [options]
        RES_ID_FIRST="$1"
        RES_ID_THEN="$2"
        KIND="${3,,}" #to lowercase

        if pcs constraint order show --full | grep "id:order-${RES_ID_FIRST}-${RES_ID_THEN}-${KIND^}" &> /dev/null; then
                echo "ordering constraint for ${RES_ID_FIRST} before ${RES_ID_THEN}: already exists, skipping"
                return
        fi

        echo "ordering constraint for ${RES_ID_FIRST} before ${RES_ID_THEN}: setting up"
        pcs constraint order "${RES_ID_FIRST}" then "${RES_ID_THEN}" "kind=${KIND^}" > /dev/null || return $?
}

pcs_constraint_colocation() {
        #pcs constraint colocation add <source resource id> with <target resource id> [score] [options] [id=constraint-id]
        RES_ID_SRC="$1"
        RES_ID_DST="$2"
        SCORE="$3"

        if pcs constraint colocation show --full | grep "id:colocation-${RES_ID_SRC}-${RES_ID_DST}-${SCORE}" &> /dev/null; then
                echo "colocation constraint for ${RES_ID_SRC} where ${RES_ID_DST}: already exists, skipping"
                return
        fi

        echo "colocation constraint for ${RES_ID_SRC} where ${RES_ID_DST}: setting up"
        pcs constraint colocation add "${RES_ID_SRC}" with "${RES_ID_DST}" "${SCORE}" > /dev/null || return $?
}


################################################################################
#Bash version check
if [ ${BASH_VERSINFO[0]} -lt 4 ]; then
        error "you need at least Bash 4.0 to run this script"
        exit 1
fi

#initialization, default argument values
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONF_FILE="${DIR}/install.conf"
PROGRAMS=(libnf-info ipfixcol fdistdump corosync pacemakerd pcs glusterd gluster ip hostname uname crm_attribute xmllint chown)
LIBRARIES=(libnf libcpg)
USER="hacluster"
GROUP="$(id -gn "${USER}")"

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
        error "cannot open configuration file \"${CONF_FILE}\""
        exit 1
fi

#parse configuration file
parse_config "${CONF_FILE}"
check_config || exit $RC

OUT_PREFIX="<$(uname -n)>"
#replicate this script and the configuration file to all nodes
if [ -z "${SSH}" ]; then
        OUT_PREFIX="[${COMMAND%% *}]"
        check_network || exit $?

        for NODE in ${ALL_NODES[*]}
        do
                scp -o "StrictHostKeyChecking no" "${0}" "${CONF_FILE}" "${NODE}:/tmp/" &> /dev/null &
        done
        wait
fi

#execute supplied command (it is supposed to be a function defined in this script)
${COMMAND} 2>&1 | sed "s/^/${OUT_PREFIX} /"
RC=${PIPESTATUS[0]} #exit with COMMAND exit status, not sed

if [ -z "${SSH}" ]; then
        if [ $RC -eq 0 ]; then
                echo "It seems that everyting went OK!"
        else
                echo "It seems that something went wrong!"
                echo "You can try to run the script again."
        fi
fi

exit $RC


################################################################################
#delete all resources
#IDS=$(pcs resource --full | grep "\(Resource\)\|\(Clone\):" | sed "s/[^:]*: \([^ ]*\).*/\1/")
#for ID in ${IDS}
#do
#        pcs resource delete "$ID"
#done

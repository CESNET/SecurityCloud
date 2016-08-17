#!/usr/bin/env sh

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

#OCF Resource Agent compliant resource script.

#OCF instance parameters:
#       OCF_RESKEY_role
#       OCF_RESKEY_startup_conf
#       OCF_RESKEY_internal_conf
#       OCF_RESKEY_ipfix_elements
#       OCF_RESKEY_verbosity
#       OCF_RESKEY_additional_args
#       OCF_RESKEY_user
#       OCF_RESKEY_group
#######################################################################


ipfixcol_start() {
        local ARGS="-d" #always deamonize
        local PIDFILE="${HA_VARRUN}/ipfixcol/${OCF_RESKEY_role}.pid"
        local TIMEOUT=2 #start timeout
        local RC

        ocf_log debug "${LOG_PREFIX}ipfixcol_start()"

        #if binary not found, exit with $OCF_ERR_INSTALLED
        check_binary "$IPFIXCOL_BIN"

        #construct arguments
        [ -n "$OCF_RESKEY_startup_conf" ] && ARGS="${ARGS} -c \"${OCF_RESKEY_startup_conf}\""
        [ -n "$OCF_RESKEY_internal_conf" ] && ARGS="${ARGS} -i \"${OCF_RESKEY_internal_conf}\""
        [ -n "$OCF_RESKEY_ipfix_elements" ] && ARGS="${ARGS} -e \"${OCF_RESKEY_ipfix_elements}\""
        [ -n "$OCF_RESKEY_verbosity" ] && ARGS="${ARGS} -v ${OCF_RESKEY_verbosity}"
        [ -n "$OCF_RESKEY_additional_args" ] && ARGS="${ARGS} ${OCF_RESKEY_additional_args}"
        ARGS="${ARGS} -p \"${PIDFILE}\""

        ipfixcol_monitor
        if [ $? -eq 1 ] #check if ipfixcol is already running
        then
                ocf_log info "${LOG_PREFIX}already running"
                return $OCF_SUCCESS
        fi

        #non root users cannon write directly to /var/run/
        ocf_log debug "${LOG_PREFIX}creating PIDfile directory " \
                "$(dirname "${PIDFILE}") as a ${OCF_RESKEY_user}":"${OCF_RESKEY_group}"
        mkdir -p "$(dirname "${PIDFILE}")"
        chown "${OCF_RESKEY_user}":"${OCF_RESKEY_group}" "$(dirname "${PIDFILE}")"

        #start ipfixcol
        ocf_log info "${LOG_PREFIX}starting ${IPFIXCOL_BIN} ${ARGS} as user ${OCF_RESKEY_user}"
        OUT=$(su -s /usr/bin/sh -c "${IPFIXCOL_BIN} ${ARGS}" "${OCF_RESKEY_user}" 2>&1)
        RC=$?
        #return code of ipfixcol is always 0 because of deamon, but test it anyway :)
        if [ $RC -ne 0 ]
        then
                ERR="IPFIXcol start failed, RC = ${RC}, OUT = ${OUT}"
                ocf_log err "${LOG_PREFIX}${ERR}"
                ocf_exit_reason "${ERR}"
                return $OCF_ERR_GENERIC
        fi

        sleep "${TIMEOUT}" #wait for startup
        #TODO: should we perform after startup monitor?
        #ipfixcol_monitor
        #if [ $? -ne 1 ]
        #then
        #        ERR="after startup monitor failed"
        #        ocf_log err "${LOG_PREFIX}${ERR}"
        #        ocf_exit_reason "${ERR}"
        #        return $OCF_ERR_GENERIC
        #fi

        return $OCF_SUCCESS
}

ipfixcol_stop() {
        local PIDFILE="${HA_VARRUN}/ipfixcol/${OCF_RESKEY_role}.pid"
        local PIDLIST
        local TIMEOUT=5 #stop timeout
        local WAITING=0

        ocf_log debug "${LOG_PREFIX}ipfixcol_stop()"

        ipfixcol_monitor
        if [ $? -eq 0 ] #check if ipfixcol is already stopped
        then
                ocf_log info "${LOG_PREFIX}not running"
                return $OCF_SUCCESS
        fi

        PIDLIST=$(cat "$PIDFILE" | tr "\n" " ") #pidfile should exist

        #first use SIGTERM, if not successfull then use SIGKILL on PIDs from pidfile
        for SIGNAL in TERM KILL
        do
                ocf_log info "${LOG_PREFIX}sending SIG${SIGNAL} to PIDs $PIDLIST"
                kill -s ${SIGNAL} $PIDLIST

                while [ $WAITING -lt $TIMEOUT ]
                do
                        sleep 1
                        WAITING=$((WAITING+1))

                        ipfixcol_monitor
                        if [ $? -eq 0 ]
                        then
                                ocf_log info "${LOG_PREFIX}SIG${SIGNAL} successfully stopped all PIDs"
                                rm -f "${PIDFILE}" #in case IPFIXcol didn't delete it
                                return $OCF_SUCCESS
                        fi
                done

                ocf_log warn "${LOG_PREFIX}SIG${SIGNAL} failed to stop all PIDs"
        done

        ERR="failed to stop"
        ocf_log err "${LOG_PREFIX}${ERR}"
        ocf_exit_reason "${ERR}"
        return $OCF_ERR_GENERIC
}

ipfixcol_monitor() {
        local PIDFILE="${HA_VARRUN}/ipfixcol/${OCF_RESKEY_role}.pid"
        local PROC_PIDFILE_CNT #number of PIDs in pidfile
        local PROC_RUNNING_CNT=0 #number of running processes

        ocf_log debug "${LOG_PREFIX}ipfixcol_monitor()"

        #does pidfile exist?
        [ -f "$PIDFILE" ] || return 0 #no pidfile, nothing should be running
        ocf_log debug "${LOG_PREFIX}(monitor) have pidfile"

        PROC_PIDFILE_CNT=$(wc -l "$PIDFILE" | cut "-d " -f 1)

        for PID in $(cat "${PIDFILE}")
        do
                kill -s 0 "${PID}" 2> /dev/null
                [ $? -eq 0 ] && PROC_RUNNING_CNT=$((PROC_RUNNING_CNT+1))
        done

        if [ $PROC_RUNNING_CNT -eq 0 ]
        then
                #no process from pidfile is running, delete it
                ocf_log debug "${LOG_PREFIX}(monitor) no process from pidfile is running, deleteting pidfile"
                rm -f "${PIDFILE}"
                return 0
        elif [ $PROC_RUNNING_CNT -eq $PROC_PIDFILE_CNT ]
        then
                #all processes from pidfile are running
                ocf_log debug "${LOG_PREFIX}(monitor) all processes from pidfile are running"
                return 1
        else
                #some processes are running, some not
                ocf_log warn "${LOG_PREFIX}some PIDs from pidfile are running, some not"
                return 2
        fi
}

ipfixcol_metadata() {
        #fancifully written "ipfixcol.metadata"
        local METADATA_FILE=$(echo $0 | sed 's/^\(.*\)\.sh$/\1.metadata/')

        ocf_log debug "${LOG_PREFIX}ipfixcol_metadata()"

        if [ ! -f "$METADATA_FILE" ]
        then
                ERR="metadata file \"${METADATA_FILE}\" doesn't exist"
                ocf_log err "${LOG_PREFIX}${ERR}"
                ocf_exit_reason "${ERR}"
                return $OCF_ERR_GENERIC
        else
                cat "$METADATA_FILE"
                return $OCF_SUCCESS
        fi
}

ipfixcol_validate_shallow() {
        ocf_log debug "${LOG_PREFIX}ipfixcol_validate_shallow()"

        #correct role test
        if [ "$OCF_RESKEY_role" != proxy -a "$OCF_RESKEY_role" != subcollector ]
        then
                ERR="invalid role \"${OCF_RESKEY_role}\""
                ocf_log err "${LOG_PREFIX}${ERR}"
                ocf_exit_reason "${ERR}"
                return $OCF_ERR_ARGS
        fi

        #verbosity integer test
        case $OCF_RESKEY_verbosity in
                *[!0-9]*)
                        ERR="invalid verbosity value: \"${OCF_RESKEY_verbosity}\""
                        ocf_log err "${LOG_PREFIX}${ERR}"
                        ocf_exit_reason "${ERR}"
                        return $OCF_ERR_ARGS
                        ;;
        esac

        #user existence test
        if ! getent passwd "${OCF_RESKEY_user}" >/dev/null; then
                ERR="user \"${OCF_RESKEY_user}\" doesn't exist"
                ocf_log err "${LOG_PREFIX}${ERR}"
                ocf_exit_reason "${ERR}"
                return $OCF_ERR_ARGS
        fi

        #group existence test
        if ! getent group "${OCF_RESKEY_group}" >/dev/null; then
                ERR="group \"${OCF_RESKEY_group}\" doesn't exist"
                ocf_log err "${LOG_PREFIX}${ERR}"
                ocf_exit_reason "${ERR}"
                return $OCF_ERR_ARGS
        fi

        return $OCF_SUCCESS
}

ipfixcol_validate_deep() {
        ocf_log debug "${LOG_PREFIX}ipfixcol_validate_deep()"

        ipfixcol_validate_shallow || return $?

        if [ -n "$OCF_RESKEY_startup_conf" -a ! -f "$OCF_RESKEY_startup_conf" ]
        then #defined but file doesn't exist
                ERR="startup configuration file doesn't exist: \"${OCF_RESKEY_startup_conf}\""
                ocf_log err "${LOG_PREFIX}${ERR}"
                ocf_exit_reason "${ERR}"
                return $OCF_ERR_ARGS
        fi

        if [ -n "$OCF_RESKEY_internal_conf" -a ! -f "$OCF_RESKEY_internal_conf" ]
        then #defined but file doesn't exist
                ERR="internal configuration file doesn't exist: \"${OCF_RESKEY_internal_conf}\""
                ocf_log err "${LOG_PREFIX}${ERR}"
                ocf_exit_reason "${ERR}"
                return $OCF_ERR_ARGS
        fi

        if [ -n "$OCF_RESKEY_ipfix_elements" -a ! -f "$OCF_RESKEY_ipfix_elements" ]
        then #defined but file doesn't exist
                ERR="IPFIX elements set file doesn't exist: \"${OCF_RESKEY_ipfix_elements}\""
                ocf_log err "${LOG_PREFIX}${ERR}"
                ocf_exit_reason "${ERR}"
                return $OCF_ERR_ARGS
        fi

        #how to test $OCF_RESKEY_additional_args?

        return $OCF_SUCCESS
}

ipfixcol_main() {
        ocf_log debug "${LOG_PREFIX}ipfixcol_main()"

        #no validation on meta-data action
        case "$1" in
                meta-data)
                        #print metadata
                        ipfixcol_metadata
                        return $?
                        ;;
        esac

        #shallow validation on stop and monitor
        ipfixcol_validate_shallow || return $?

        case "$1" in
                stop)
                        #stop collector process
                        ipfixcol_stop
                        return $?
                        ;;
                monitor)
                        #monitor collector status
                        ipfixcol_monitor
                        case "$?" in
                                0) return $OCF_NOT_RUNNING;;
                                1) return $OCF_SUCCESS;;
                                2) return $OCF_NOT_RUNNING;;
                        esac
                        ;;
        esac

        #deep validation on start and validate-all
        ipfixcol_validate_deep || return $?

        case "$1" in
                start)
                        #start collector process
                        ipfixcol_start
                        return $?
                        ;;
                validate-all)
                        #already validated
                        return $OCF_SUCCESS
                        ;;
                *)
                        #anything else is error
                        ERR="unimplemented OCF action"
                        ocf_log err "${LOG_PREFIX}${ERR}"
                        ocf_exit_reason "${ERR}"
                        return $OCF_ERR_UNIMPLEMENTED
                        ;;
        esac
}

#######################################################################

#initialization
: ${OCF_FUNCTIONS_DIR=${OCF_ROOT}/lib/heartbeat}
. ${OCF_FUNCTIONS_DIR}/ocf-shellfuncs

#use supplied values or default values
OCF_RESKEY_user_default="hacluster"
: "${OCF_RESKEY_user="${OCF_RESKEY_user_default}"}"
: "${OCF_RESKEY_group="$(id -gn "${OCF_RESKEY_user}")"}"


IPFIXCOL_BIN=ipfixcol
LOG_PREFIX="${1} ${OCF_RESKEY_role}: "

#argument check
if [ $# -ne 1 ]
then
        ERR="bad number of arguments ($#): $*"
        ocf_log err "${LOG_PREFIX}${ERR}"
        ocf_exit_reason "${ERR}"
        exit $OCF_ERR_ARGS
else
        ocf_log debug "${LOG_PREFIX}here we go!"
fi

#call main
ipfixcol_main "$1"
RC=$?

ocf_log debug "${LOG_PREFIX}exitting (RC=${RC})"
exit $RC

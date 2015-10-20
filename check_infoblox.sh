#!/bin/bash 
############################################################################
# Script:   check_infoblox                                                 #
# Author:   Claudio Kuenzler www.claudiokuenzler.com                       #
# Purpose:  Monitor Infoblox Appliance                                     #
# License:  GPLv2                                                          #
# Docs:     www.claudiokuenzler.com/nagios-plugins/check_infoblox.php      #
# History:                                                                 #
# 20151016  Started Script programming. Check: cpu, mem                    #
# 20151020  Added check: replication, grid, info, ip                       #
############################################################################
# Variable Declaration
STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin # Set path
############################################################################
# Functions
help() {
echo -ne "
check_infoblox (c) 2015-$(date +%Y) Claudio Kuenzler (published under GPLv2 licence)

Usage: ./check_infoblox -H host -v 2c -C community -t type [-d domain] [-w warning] [-c critical]

Options:
------------
-H Hostname
-V SNMP Version to use (currently only 2c is supported)
-C SNMP Community (default: public)
-t Type to check 
-a Additional arguments for certain checks
-w Warning Threshold (optional)
-c Critical Threshold (optional)
-h This help text

Check Types:
------------
cpu -> Check CPU utilization (thresholds possible)
mem -> Check Memory utilization (thresholds possible)
replication -> Check if replication between Infoblox appliances is working
grid -> Check if appliance is Active or Passive in grid (additional argument possible)
info -> Display general information about this appliance
ip -> Display configured ip addresses of this appliance (additional argument possible to check for a certain address)

Additional Arguments:
------------
example.com (domain name) for dnsstat check
(Active|Passive) for grid check
ip.add.re.ss for ip check
"
exit ${STATE_UNKNOWN} 
}
############################################################################
# Was there some input?
if [[ "$1" = "--help" ]] || [[ ${#} -eq 0 ]]; then help; fi

# Get Opts
while getopts "H:V:C:t:a:w:c:h" Input;
do
  case ${Input} in
    H) host=${OPTARG};;
    V) snmpv=${OPTARG};;
    C) snmpc=${OPTARG};;
    t) checktype=${OPTARG};;
    a) addarg=${OPTARG};;
    w) warning=${OPTARG};;
    c) critical=${OPTARG};;
    h) help;;
    *) echo "Wrong option given. Use -h to check out help."; exit ${STATE_UNKNOWN};;

  esac
done
############################################################################
# Pre-Checks before doing any actual work

# The following commands must exist
for cmd in snmpwalk awk grep egrep sed; do 
  if ! `which ${cmd} 1>/dev/null`; then 
    echo "UNKNOWN - ${cmd} does not exist. Please verify if command exists in PATH"
    exit ${STATE_UNKNOWN}
  fi 
done

# Check for required opts
if [[ -z $host ]] || [[ -z $snmpv ]] || [[ -z $snmpc ]] || [[ -z $checktype ]]
then echo "UNKNOWN - Missing required option. Use -h to check out help."; exit ${STATE_UNKNOWN}
fi

# Currently only snmp version 2c is allowed
if [[ "$snmpv" != "2c" ]]; then echo "UNKNOWN - Sorry, only snmp version 2c allowed for now"; exit ${STATE_UNKNOWN}; fi

# Manually set snmpv to 2c if not set
if [[ -z $snmpv ]]; then snmpv="2c"; fi

# Default snmp community is public if not set
if [[ -z $snmpc ]]; then snmpc="public"; fi

# SNMP Connection check (also being used to get sysName)
systemname=$(snmpwalk -v ${snmpv} -Oqv -c ${snmpc} ${host} 1.3.6.1.2.1.1.5 2>/dev/null)
if [[ $? -gt 0 ]]; then echo "UNKNOWN - SNMP connection failed"; exit ${STATE_UNKNOWN};fi
############################################################################
# Check Types
case ${checktype} in

info) # Displays information about this Infoblox appliance
  model=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.4.0)
  hwn=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.5.0)
  systemsn=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.6.0)
  softv=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.7.0)
  echo "System Name: $systemname, Infoblox Model: $model, HW ID: $hwn, SN: $systemsn, Software Version: $softv"
  exit ${STATE_OK}
;;

ip) # Display configured ip addresses of this appliance
  ipaddrs=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.2.1.4.20.1.1))
  if [[ -n $addarg ]]; then 
    if [[ -z $(echo ${ipaddrs[*]} | grep $addarg) ]]; then
      echo "IP WARNING: Expected address $addarg not found. IP addresses configured: ${ipaddrs[*]}" 
      exit ${STATE_WARNING}
    else 
      echo "IP OK: Addresses: ${ipaddrs[*]}"
      exit ${STATE_OK} 
    fi 
  else
    echo "IP OK - Addresses: ${ipaddrs[*]}"
  fi
  exit ${STATE_OK}
;;

cpu) # Checks the cpu utilization in percentage
  usage=$(snmpwalk -v ${snmpv} -c ${snmpc} -Oqv ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.8.1)

  if [[ -n ${warning} ]] || [[ -n ${critical} ]]
  then # Check CPU utilization with thresholds
    if [[ ${usage} -ge ${critical} ]]; then 
      echo "CPU CRITICAL - Usage at ${usage}|ibloxcpu=${usage}%;${warning};${critical};;"
      exit ${STATE_CRITICAL}
    elif [[ ${usage} -ge ${warning} ]]; then
      echo "CPU WARNING - Usage at ${usage}|ibloxcpu=${usage}%;${warning};${critical};;"
      exit ${STATE_WARNING}
    else 
      echo "CPU OK - Usage at ${usage}|ibloxcpu=${usage}%;${warning};${critical};;"
      exit ${STATE_OK}
    fi
  else # No thresholds, just show current utilization
    echo "CPU OK - Usage at ${usage}|ibloxcpu=${usage}%;${warning};${critical};;"
    exit ${STATE_OK}
  fi
;;

mem) # Checks the memory utilization in percentage
  usage=$(snmpwalk -v ${snmpv} -c ${snmpc} -Oqv ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.8.2)

  if [[ -n ${warning} ]] || [[ -n ${critical} ]]
  then # Check memory utilization with thresholds
    if [[ ${usage} -ge ${critical} ]]; then
      echo "MEMORY CRITICAL - Usage at ${usage}|ibloxmem=${usage}%;${warning};${critical};;"
      exit ${STATE_CRITICAL}
    elif [[ ${usage} -ge ${warning} ]]; then
      echo "MEMORY WARNING - Usage at ${usage}|ibloxmem=${usage}%;${warning};${critical};;"
      exit ${STATE_WARNING}
    else
      echo "MEMORY OK - Usage at ${usage}|ibloxmem=${usage}%;${warning};${critical};;"
      exit ${STATE_OK}
    fi
  else # No thresholds, just show current utilization
    echo "MEMORY OK - Usage at ${usage}|ibloxmem=${usage}%;${warning};${critical};;"
    exit ${STATE_OK}
  fi
;;

replication) # Check the replication between Infoblox master/slave appliances
  # Replication status can only be checked if this host is "Active" in the grid 
  gridstatus=$(snmpwalk -v ${snmpv} -c ${snmpc} -Oqv ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.13 | sed "s/\"//g")
  if [[ "${gridstatus}" = "Active" ]]
  then
    replstatus=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.2.1.2 | sed "s/\"//g"))
    # Determine which array index is offline
    r=0; for status in ${replstatus[*]}; do
      if [[ "${status}" = "Offline" ]]; then errorindex[${r}]=${r}; fi 
      let r++
    done
    if [[ ${#errorindex[*]} -gt 0 ]] 
    then 
      SAVEIFS=$IFS; IFS=$(echo -en "\n\b") # <- Do not use whitespace as split
      replmembers=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.2.1.1))
      repllast=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.2.1.4))
      IFS=$SAVEIFS
      for f in ${errorindex[*]}; do 
        failedmembers[${f}]=$(echo ${replmembers[$f]})
        failedtime[${f}]=$(echo ${repllast[$f]})
      done
      echo "REPLICATION CRITICAL - Member(s) ${failedmembers[*]} failed to replicate. Last successful sync at ${failedtime[*]}"
      exit ${STATE_CRITICAL}
    else
      echo "REPLICATION OK"
      exit ${STATE_OK}
    fi
  else 
    systemsn=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.6.0)
    echo "REPLICATION UNKNOWN - This system (SN: ${systemsn}) is a passive grid member. Cannot verify replication. Try with HA IP address?"
    exit ${STATE_UNKNOWN}
  fi
;;

grid) # Check grid status
  gridstatus=$(snmpwalk -v ${snmpv} -c ${snmpc} -Oqv ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.13 | sed "s/\"//g")
  systemsn=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.6.0)
  if [[ -n $addarg ]] && ([[ "$addarg" = "Active" ]] || [[ "$addarg" = "Passive" ]]); then
    if [[ "$gridstatus" != "$addarg" ]]; then
      echo "GRID STATUS WARNING - This member (SN: $systemsn) is $gridstatus but expected $addarg"
      exit ${STATE_WARNING}
    fi
  elif [[ -n $addarg ]]; then 
    echo "GRID STATUS UNKNOWN - Please use Active or Passive as additional arguments"
    exit ${STATE_UNKNOWN}
  else 
    echo "GRID STATUS OK - This member (SN: $systemsn) is $gridstatus"
    exit ${STATE_OK}
  fi


    

  
;;

esac

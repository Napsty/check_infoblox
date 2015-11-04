#!/bin/bash 
############################################################################
# Script:   check_infoblox                                                 #
# Author:   Claudio Kuenzler www.claudiokuenzler.com                       #
# Purpose:  Monitor Infoblox Appliance                                     #
# License:  GPLv2                                                          #
# Docs:     www.claudiokuenzler.com/nagios-plugins/check_infoblox.php      #
# History:                                                                 #
# 20151016  Started Script programming. Check: cpu, mem                    #
# 20151020  Added check: replication, grid, info, ip, dnsstat, temp        #
# 20151021  (Back to the Future Day!) Public release                       #
# 20151030  Added check dhcpstat (by Chris Lewis)                          #
# 20151104  Bugfix in perfdata of dnsstat check                            #
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

Usage: ./check_infoblox -H host -v 2c -C community -t type [-a argument] [-w warning] [-c critical]

Options:
------------
-H Hostname
-V SNMP Version to use (currently only 2c is supported)
-C SNMP Community (default: public)
-t Type to check 
-a Additional arguments for certain checks
-w Warning Threshold (optional)
-c Critical Threshold (optional)
-i Ignore Unknown Status (for 'replication' and 'dnsstat' checks)
-h This help text

Check Types:
------------
cpu -> Check CPU utilization (thresholds possible)
mem -> Check Memory utilization (thresholds possible)
replication -> Check if replication between Infoblox appliances is working
grid -> Check if appliance is Active or Passive in grid (additional argument possible)
info -> Display general information about this appliance
ip -> Display configured ip addresses of this appliance (additional argument possible to check for a certain address)
dnsstat -> Display DNS statistics for domain (use in combination with -a domain)
dhcpstat -> Display DHCP statistics 

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
while getopts "H:V:C:t:a:w:c:ih" Input;
do
  case ${Input} in
    H) host=${OPTARG};;
    V) snmpv=${OPTARG};;
    C) snmpc=${OPTARG};;
    t) checktype=${OPTARG};;
    a) addarg=${OPTARG};;
    w) warning=${OPTARG};;
    c) critical=${OPTARG};;
    i) ignoreunknown=true;;
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
      echo "CPU CRITICAL - Usage at ${usage}%|ibloxcpu=${usage}%;${warning};${critical};;"
      exit ${STATE_CRITICAL}
    elif [[ ${usage} -ge ${warning} ]]; then
      echo "CPU WARNING - Usage at ${usage}%|ibloxcpu=${usage}%;${warning};${critical};;"
      exit ${STATE_WARNING}
    else 
      echo "CPU OK - Usage at ${usage}%|ibloxcpu=${usage}%;${warning};${critical};;"
      exit ${STATE_OK}
    fi
  else # No thresholds, just show current utilization
    echo "CPU OK - Usage at ${usage}%|ibloxcpu=${usage}%;${warning};${critical};;"
    exit ${STATE_OK}
  fi
;;

mem) # Checks the memory utilization in percentage
  usage=$(snmpwalk -v ${snmpv} -c ${snmpc} -Oqv ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.8.2)

  if [[ -n ${warning} ]] || [[ -n ${critical} ]]
  then # Check memory utilization with thresholds
    if [[ ${usage} -ge ${critical} ]]; then
      echo "MEMORY CRITICAL - Usage at ${usage}%|ibloxmem=${usage}%;${warning};${critical};;"
      exit ${STATE_CRITICAL}
    elif [[ ${usage} -ge ${warning} ]]; then
      echo "MEMORY WARNING - Usage at ${usage}%|ibloxmem=${usage}%;${warning};${critical};;"
      exit ${STATE_WARNING}
    else
      echo "MEMORY OK - Usage at ${usage}%|ibloxmem=${usage}%;${warning};${critical};;"
      exit ${STATE_OK}
    fi
  else # No thresholds, just show current utilization
    echo "MEMORY OK - Usage at ${usage}%|ibloxmem=${usage}%;${warning};${critical};;"
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
    if [[ -n $ignoreunknown ]]; then exit ${STATE_OK}; else exit ${STATE_UNKNOWN}; fi
  fi
;;

grid) # Check grid status
  gridstatus=$(snmpwalk -v ${snmpv} -c ${snmpc} -Oqv ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.13 | sed "s/\"//g")
  systemsn=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.6.0)
  if [[ -n $addarg ]] && ([[ "$addarg" = "Active" ]] || [[ "$addarg" = "Passive" ]]); then
    if [[ "$gridstatus" != "$addarg" ]]; then
      echo "GRID STATUS WARNING - This member (SN: $systemsn) is $gridstatus but expected $addarg"
      exit ${STATE_WARNING}
    else
      echo "GRID STATUS OK - This member (SN: $systemsn) is $gridstatus"
      exit ${STATE_OK}
    fi
  elif [[ -n $addarg ]]; then 
    echo "GRID STATUS UNKNOWN - Please use Active or Passive as additional arguments"
    exit ${STATE_UNKNOWN}
  else 
    echo "GRID STATUS OK - This member (SN: $systemsn) is $gridstatus"
    exit ${STATE_OK}
  fi
;;

dnsstat) # Get DNS statistics for a domain
  # Need domain name as additional argument
  if [[ -z $addarg ]]; then 
    echo "No domain name given. Please use '-a domain' in combination with dnsstat check." 
    exit ${STATE_UNKNOWN}
  fi
  
  # DNS Stats can only be retrieved if this appliance is "Active" in the grid 
  gridstatus=$(snmpwalk -v ${snmpv} -c ${snmpc} -Oqv ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.13 | sed "s/\"//g")
  systemsn=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.6.0)
  if [[ "${gridstatus}" = "Passive" ]]; then 
    echo "DNS STATS UNKNOWN - This system (SN: ${systemsn}) is a passive grid member. DNS Stats only work on Active member."
    if [[ -n $ignoreunknown ]]; then exit ${STATE_OK}; else exit ${STATE_UNKNOWN}; fi
  fi

  domainoid=$(snmpwalk -On -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.3.1.1.1.1 | grep \"${addarg}\"$ | awk '{print $1}'|awk -F ".1.3.6.1.4.1.7779.3.1.1.3.1.1.1.1" '{print $2}')

  if [[ -z $domainoid ]]; then 
    echo "DNS STATS WARNING - Could not find domain $addarg"
    exit ${STATE_WARNING}
  fi

  # Number of Successful responses since DNS process started
  success=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.3.1.1.1.2${domainoid}))
  # Number of DNS referrals since DNS process started
  referral=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.3.1.1.1.3${domainoid}))
  # Number of DNS query received for non-existent record
  nxrrset=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.3.1.1.1.4${domainoid}))
  # Number of DNS query received for non-existent domain
  nxdomain=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.3.1.1.1.5${domainoid}))
  #Number of Queries received using recursion since DNS process started
  recursion=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.3.1.1.1.6${domainoid}))
  # Number of Failed queries since DNS process started
  failure=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.3.1.1.1.7${domainoid}))

  echo "DNS STATS OK - $addarg Success: $success, Referral: $referral, NxRRset: $nxrrset, NxDomain: $nxdomain, Recursion: $recursion, Failure: $failure|${addarg}_success=$success;;;; ${addarg}_referral=$referral;;;; ${addarg}_nxrrset=$nxrrset;;;; ${addarg}_nxdomain=$nxdomain;;;; ${addarg}_recursion=$recursion;;;; ${addarg}_failure=$failure" 
  exit ${STATE_OK}
;;

temp) # Checks the temperature of the appliance (makes only sense in physical appliance, d'uh!)
  temp=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.1.0 | sed "s/\"//g" | awk -F'[^0-9]*' '$0=$2')

  if [[ -n ${warning} ]] || [[ -n ${critical} ]]; then
    if [[ ${temp} -ge ${critical} ]]; then 
      echo "TEMP CRITICAL - Temperature is at $temp|temperature=$temp;$warning;$critical;;"
      exit ${STATE_CRITICAL} 
    elif [[ ${temp} -ge ${warning} ]]; then
      echo "TEMP WARNING - Temperature is at $temp|temperature=$temp;$warning;$critical;;"
      exit ${STATE_WARNING} 
    else
      echo "TEMP OK - Temperature is at $temp|temperature=$temp;$warning;$critical;;"
      exit ${STATE_OK} 
    fi
  else 
    echo "TEMP OK - Temperature is at $temp|temperature=$temp;$warning;$critical;;"
    exit ${STATE_OK} 
  fi
;;

dhcpstat) # Get DHCP statistics for a domain
  # DHCP Stats can only be retrieved if this appliance is "Active" in the grid
  gridstatus=$(snmpwalk -v ${snmpv} -c ${snmpc} -Oqv ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.13 | sed "s/\"//g")
  systemsn=$(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.2.1.6.0)
  if [[ "${gridstatus}" = "Passive" ]]; then
    echo "DHCP STATS UNKNOWN - This system (SN: ${systemsn}) is a passive grid member. DHCP Stats only work on Active member."
    if [[ -n $ignoreunknown ]]; then exit ${STATE_OK}; else exit ${STATE_UNKNOWN}; fi
  fi
  # ibDhcpTotalNoOfDiscovers
  discovers=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.4.1.3.1.0))
  # ibDhcpTotalNoOfRequests
  requests=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.4.1.3.2.0))
  #ibDhcpTotalNoOfReleases
  releases=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.4.1.3.3.0))
  # ibDhcpTotalNoOfOffers
  offers=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.4.1.3.4.0))
  #ibDhcpTotalNoOfAcks
  acks=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.4.1.3.5.0))
  #ibDhcpTotalNoOfNacks
  nacks=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.4.1.3.6.0))
  # ibDhcpTotalNoOfDeclines
  declines=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.4.1.3.7.0))
  # ibDhcpTotalNoOfInforms
  informs=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.4.1.3.8.0))
  # ibDhcpTotalNoOfOthers
  others=($(snmpwalk -Oqv -v ${snmpv} -c ${snmpc} ${host} 1.3.6.1.4.1.7779.3.1.1.4.1.3.9.0))

  echo "DHCP STATS OK - $addarg Discovers: $discovers, Requests: $requests, Releases: $releases, Offers: $offers, Acks: $acks, Nacks: $nacks, Declines: $declines, Informs: $informs, Other: $other|discovers=$discovers; requests=$requests; releases=$releases; offers=$offers; acks=$acks nacks=$nacks; declines=$declines; informs=$informs others=$others"
  exit ${STATE_OK}
;;

esac

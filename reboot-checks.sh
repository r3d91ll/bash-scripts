#!/bin/bash

##
## reboot-checks.sh v1.0
## Created/Maintained by Shayne Hardesty (shayne.hardesty@rackspace.com)
##
## PURPOSE: run against a server prior to maintenance prep or QC to check for common issues
## that cause problems during maintenances.
##
## USAGE: ht --sudo-make-me-a-sandwich -s reboot-checks.sh <ticket|account|server(s)>
## - OR - simply copy the script to the server and run it as root
##
## WARNING: this script is only intended to HELP you in the prep/QC process.  It is NOT a
## replacement for performing your own checks and common sense.  I take NO responsiblity
## for maintenance issues which arise from the use of this script.  I encourage you to
## read through all of the checks, understand them, and make your own determination
## if this script is right for you.  USE AT YOUR OWN RISK!
##
## UPDATES: Pull requests are accepted provided they meet the coding guidelines here:
## https://github.rackspace.com/SupportTools/linserverscripts
##
## IMPACT: Running this script should *generally* be safe on any server, as it only examines
## various aspects of the server and makes recommendations.  I have tested it on hundreds
## of production servers over the past few months with no issues.  It is designed to not
## actively make any changes to a server, so it should be safe even for environments with
## strict change control policies.  However, as above, USE AT YOUR OWN RISK.
##


echo "--- Checking system release --"
grep -v ^# /etc/*-release | head -n 1
echo

echo "--- Checking for unsupported repositories ---"; echo
yum -C repolist 2>/dev/null | egrep -v '^(Loaded plugins|repolist|Excluding|Finished)' | egrep -v '^(rackspace|managed|rhel|rhn-tools|vmware-tools|ius|res5|epel)'
echo

echo "--- Checking for services not set to start on boot ---"; echo

declare -a MANUAL_PROCS

RUNLEVEL=$(/sbin/runlevel | awk '{print $2}')
echo "Current runlevel: $RUNLEVEL"; echo

for SVC in `netstat -plunt | grep LISTEN | awk '{n=split($7,a,"/"); print a[n]}' | sort -u | egrep -v '(cvd|EvMgr|master|nimbus)'`; do

   [ $SVC == "-" ] && continue

   ## some services us different names for the init scripts
   [ "$SVC" == "cupsd" ] && SVC=cups
   [ "$SVC" == "ccsd" ] && SVC=cman
   [ "$SVC" == "imap-login" ] && SVC=dovecot
   [ "$SVC" == "pop3-login" ] && SVC=dovecot
   [ "$SVC" == "mrouter" ] && SVC=sav-rms
   [ "$SVC" == "magent" ] && SVC=sav-rms
   [ "$SVC" == "savwebd" ] && SVC=sav-web
   [ "$SVC" == "al-slc" ] && SVC=al-log-agent
   [ "$SVC" == "rpc.statd" ] && SVC=nfslock
   [ "$SVC" == "rpc.mountd" ] && SVC=nfs
   [ "$SVC" == "rpc.rquotad" ] && SVC=nfs
   [ "$SVC" == "sfcbd" ] && SVC=sblim-sfcb
   [ "$SVC" == "redis-server" ] && SVC=redis
   [ "$SVC" == "sendmail:" ] && SVC=sendmail
   [ "$SVC" == "rsyslogd" ] && SVC=rsyslog

   ## perl processes require a little more digging
   if [ "$SVC" == "perl" ]; then
      SVCARG=$(ps auxww | grep [p]erl | awk '{print $12}')
      [ "$(basename $SVCARG)" == "miniserv.pl" ] && SVC=webmin
      [ "$(basename $SVCARG)" == "mysql_replication.pl" ] && SVC=nimbus
   fi

   if [ ! -f /etc/init.d/$SVC ]; then
      MANUAL_PROCS+=($SVC)
      continue
   fi

   if [ -z $RUNLEVEL ]; then
     ## sometimes we can't determine the runlevel - if so just list the services
     /sbin/chkconfig --list $SVC
   else
     /sbin/chkconfig --list $SVC | grep -v "${RUNLEVEL}:on"
   fi
done
echo

if [ ${#MANUAL_PROCS[@]} > 0 ]; then
  echo "* These processes may not have init scripts, so they require manual investigation:"; echo

  for PROC in ${MANUAL_PROCS[@]}; do
    ps aux --width 255 | grep $PROC | grep -v grep
  done

  echo
fi

echo "--- Checking for mounts missing from /etc/fstab ---"; echo

for DEV in `awk '{print $1}' < /etc/mtab`; do
   [[ $DEV =~ ^(none|sys|proc|devpts|tmpfs|sunrpc|nfsd) ]] && continue

   if [[ ! $(grep ^$DEV /etc/fstab) ]]; then
      ## /dev/mapper LVM devices could be listed as /dev/vg/lv
      if [[ $DEV =~ ^/dev/mapper/ ]]; then
         DEV=$(echo $DEV | sed s/'mapper\/'//g | tr '-' '/' | tr -s '/')
         [[ $(grep ^$DEV /etc/fstab) ]] && continue
      fi

      ## devices might be listed by UUID, so we should check that
      UUID=$(tune2fs -l $DEV 2>/dev/null | grep "^Filesystem UUID" | awk '{print $3}')
      [[ $(grep ^UUID=$UUID /etc/fstab) ]] && continue

      ## devices might be listed by LABEL, so we should check that too
      LABEL=$(tune2fs -l $DEV 2>/dev/null | grep "^Filesystem volume name" | awk '{print $4}')
      [[ $(grep ^LABEL=$LABEL /etc/fstab) ]] && continue

      echo "$DEV not found in /etc/fstab!"
   fi
done
echo;


echo "--- Checking for other issues (RHCS/SAN/DAS/Oracle/ASM) ---"; echo

if [ -f /etc/cluster/cluster.conf ]; then
  echo "RHCS: The file /etc/cluster/cluster.conf exists. This may be a node in an RHCS cluster."
fi

# check for san
[ `/sbin/lspci | egrep -ic '(fabric|HBA)'` -gt 0 ] && echo "SAN: HBA present, approach kernel upgrades with caution"
[ "`ls /dev/emc* 2>/dev/null`" ] && echo "SAN: This server appears to be SAN attached."

# check for das (servers 375047 and 421956, for example)
#if [ "`grep mpp /proc/modules`" ]; then
if [ "`egrep '^(scsi_dh_rdac|dm_rdac)' /proc/modules`" ]; then
  echo "DAS: This server appears to be DAS attached."
fi

# check for tricky ports *cough*ORACLE*cough*
for PORT in `netstat -plunt | grep LISTEN | awk '{split($4,a,":"); print a[4] ? a[4] : a[2]}' | sort -n | uniq`; do
   [ $PORT == 1521 ] && echo "ORACLE: Found service listening on port 1521 - check for Oracle DB"
   [ $PORT == 655 ] && echo "NFS: Found service listening on port 655 - check for NFS Server (rpc.mountd)"
done

if [ -d /dev/oracleasm ]; then
  echo "ORACLEASM: Oracle ASM may be in use on this server"
fi

if [ -s /etc/exports ]; then
  echo "NFS: Non-empty /etc/exports found - check if NFS server"
  showmount -e localhost
  [ -f /var/lib/nfs/rmtab ] && cat /var/lib/nfs/rmtab
fi



exit 0

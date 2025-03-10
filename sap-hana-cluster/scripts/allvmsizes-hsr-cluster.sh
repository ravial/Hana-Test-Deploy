#!/bin/bash
set -x
# store arguments in a special array
args=("$@")
# get number of elements
ELEMENTS=${#args[@]}

# echo each element in array
# for loop
for (( i=0;i<$ELEMENTS;i++)); do
    echo "ARG[${i}]: ${args[${i}]}"
done

URI=${1}
HANAUSR=${2}
HANAPWD=${3}
HANASID=${4}
HANANUMBER=${5}
VMNAME=${6}
OTHERVMNAME=${7}
VMIPADDR=${8}
OTHERIPADDR=${9}
CONFIGHSR=${10}
ISPRIMARY=${11}
REPOURI=${12}
ISCSIIP=${13}
IQN=${14}
IQNCLIENT=${15}
LBIP=${16}
SUBEMAIL=${17}
SUBID=${18}
SUBURL=${19}
NFSIP=${20}
HANAVER=${21}
###
# cluster tuning values
WATCHDOGTIMEOUT="30"
MSGWAITTIMEOUT="60"
STONITHTIMEOUT="150s"
###
#get the VM size via the instance api
VMSIZE=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2017-08-01&format=text"`


HANASIDU="${HANASID^^}"
HANASIDL="${HANASID,,}"

HANAADMIN="$HANASIDL"adm
echo "HANAADMIN:" $HANAADMIN >>/tmp/variables.txt

echo "small.sh receiving:"
echo "URI:" $URI >> /tmp/variables.txt
echo "HANAUSR:" $HANAUSR >> /tmp/variables.txt
echo "HANAPWD:" $HANAPWD >> /tmp/variables.txt
echo "HANASID:" $HANASID >> /tmp/variables.txt
echo "HANANUMBER:" $HANANUMBER >> /tmp/variables.txt
echo "VMSIZE:" $VMSIZE >> /tmp/variables.txt
echo "VMNAME:" $VMNAME >> /tmp/variables.txt
echo "OTHERVMNAME:" $OTHERVMNAME >> /tmp/variables.txt
echo "VMIPADDR:" $VMIPADDR >> /tmp/variables.txt
echo "OTHERIPADDR:" $OTHERIPADDR >> /tmp/variables.txt
echo "CONFIGHSR:" $CONFIGHSR >> /tmp/variables.txt
echo "ISPRIMARY:" $ISPRIMARY >> /tmp/variables.txt
echo "REPOURI:" $REPOURI >> /tmp/variables.txt
echo "ISCSIIP:" $ISCSIIP >> /tmp/variables.txt
echo "IQN:" $IQN >> /tmp/variables.txt
echo "IQNCLIENT:" $IQNCLIENT >> /tmp/variables.txt
echo "LBIP:" $LBIP >> /tmp/variables.txt
echo "SUBEMAIL:" $SUBEMAIL >> /tmp/variables.txt
echo "SUBID:" $SUBID >> /tmp/variables.txt
echo "SUBURL:" $SUBURL >> /tmp/variables.txt


#!/bin/bash

retry() {
    local -r -i max_attempts="$1"; shift
    local -r cmd="$@"
    local -i attempt_num=1

    until $cmd
    do
        if (( attempt_num == max_attempts ))
        then
            echo "Attempt $attempt_num failed and there are no more attempts left!"
            return 1
        else
            echo "Attempt $attempt_num failed! Trying again in $attempt_num seconds..."
            sleep $(( attempt_num++ ))
        fi
    done
}

declare -fxr retry

waitfor() {
P_USER=$1
P_HOST=$2
P_FILESPEC=$3

RESULT=1
while [ $RESULT = 1 ]
do
    sleep 1
    ssh -q -n -o BatchMode=yes -o StrictHostKeyChecking=no "$P_USER@$P_HOST" "test -e $P_FILESPEC"
    RESULT=$?
    if [ "$RESULT" = "255" ]; then
        (>&2 echo "waitfor failed in ssh")
        return 255
    fi
done
return 0
}

declare -fxr waitfor

download_if_needed() {
  P_DESTDIR=${1}
  P_SOURCEDIR=${2}
  P_FILENAME=${3}

  DESTFILE="$P_DESTDIR/$P_FILENAME"
  SOURCEFILE="$P_SOURCEDIR/$P_FILENAME"
  test -e $DESTFILE
  RESULT=$?
  if [ "$RESULT" = "1" ]; then
    #need to download the file
    retry 5 "wget --quiet -O $DESTFILE $SOURCEFILE"
  fi
}

declare -fxr download_if_needed

##bash function definitions

register_subscription() {
  SUBEMAIL=$1
  SUBID=$2
  SUBURL=$3

#if needed, register the machine
if [ "$SUBEMAIL" != "" ]; then
  if [ "$SUBURL" = "NONE" ]; then 
    SUSEConnect -e $SUBEMAIL -r $SUBID
  else 
    if [ "$SUBURL" != "" ]; then 
      SUSEConnect -e $SUBEMAIL -r $SUBID --url $SUBURL
    else 
      SUSEConnect -e $SUBEMAIL -r $SUBID
    fi
  fi
  SUSEConnect -p sle-module-public-cloud/12/x86_64 
fi
}

write_corosync_config (){
  BINDIP=$1
  HOST1IP=$2
  HOST2IP=$3
  mv /etc/corosync/corosync.conf /etc/corosync/corosync.conf.orig 
cat > /etc/corosync/corosync.conf <<EOF
totem {
        version:        2
        secauth:        on
        crypto_hash:    sha1
        crypto_cipher:  aes256
        cluster_name:   hacluster
        clear_node_high_bit: yes
        token:          5000
        token_retransmits_before_loss_const: 10
        join:           60
        consensus:      6000
        max_messages:   20
        interface {
                ringnumber:     0
                bindnetaddr:    $BINDIP
                mcastport:      5405
                ttl:            1
        }
 transport:      udpu
}
nodelist {
  node {
   ring0_addr:$HOST1IP
   nodeid:1
  }
  node {
   ring0_addr:$HOST2IP
   nodeid:2
  }
  transport:      udpu
}

logging {
        fileline:       off
        to_stderr:      no
        to_logfile:     no
        logfile:        /var/log/cluster/corosync.log
        to_syslog:      yes
        debug:          off
        timestamp:      on
        logger_subsys {
                subsys: QUORUM
                debug:  off
        }
}
quorum {
        # Enable and configure quorum subsystem (default: off)
        # see also corosync.conf.5 and votequorum.5
        provider: corosync_votequorum
        expected_votes: 2
        two_node: 1
}
EOF

}


setup_cluster() {
  ISPRIMARY=$1
  SBDID=$2
  VMNAME=$3
  OTHERVMNAME=$4 
  CLUSTERNAME=$5 
  #node1
  if [ "$ISPRIMARY" = "yes" ]; then
    ha-cluster-init -y -q csync2
    ha-cluster-init -y -q -u corosync
    ha-cluster-init -y -q -s $SBDID sbd 
    ha-cluster-init -y -q cluster name=$CLUSTERNAME interface=eth0
    touch /tmp/corosyncconfig1.txt	
    waitfor root $OTHERVMNAME /tmp/corosyncconfig2.txt	
    systemctl stop corosync
    systemctl stop pacemaker
    write_corosync_config 10.0.5.0 $VMNAME $OTHERVMNAME
    systemctl start corosync
    systemctl start pacemaker
    touch /tmp/corosyncconfig3.txt	

    sleep 10
  else
    waitfor root $OTHERVMNAME /tmp/corosyncconfig1.txt	
    ha-cluster-join -y -q -c $OTHERVMNAME csync2 
    ha-cluster-join -y -q ssh_merge
    ha-cluster-join -y -q cluster
    systemctl stop corosync
    systemctl stop pacemaker
    touch /tmp/corosyncconfig2.txt	
    waitfor root $OTHERVMNAME /tmp/corosyncconfig3.txt	
    write_corosync_config 10.0.5.0 $OTHERVMNAME $VMNAME 
    systemctl restart corosync
    systemctl start pacemaker
  fi
}

do_zypper_update() {
  #this will update all packages but waagent and msrestazure
  zypper -q list-updates | tail -n +3 | cut -d\| -f3  >/tmp/zypperlist
  cat /tmp/zypperlist  | grep -v "python.*azure*" > /tmp/cleanlist
  cat /tmp/cleanlist | awk '{$1=$1};1' >/tmp/cleanlist2
  cat /tmp/cleanlist2 | xargs -L 1 -I '{}' zypper update -y '{}'
}

##end of bash function definitions


register_subscription "$SUBEMAIL"  "$SUBID" "$SUBURL"

#decode hana version parameter
HANAVER=${HANAVER^^}
if [ "${HANAVER}" = "SAP HANA PLATFORM EDITION 2.0 SPS01 REV 10 (51052030)" ]
then
  hanapackage="51052030"
else
  echo "not 51052030"
  if [ "$HANAVER" = "SAP HANA PLATFORM EDITION 2.0 SPS02 (51052325)" ]
  then
    hanapackage="51052325"
  else
  echo "not 51052325"
    if [ "$HANAVER" = "SAP HANA PLATFORM EDITION 2.0 SPS03 REV30 (51053061)" ]
    then
      hanapackage="51053061"
    else
      if [ "$HANAVER" = "SAP HANA PLATFORM EDITION 2.0 SPS04 REV40 (51053787)" ]
      then
        hanapackage="51053787"
      else
        echo "not 51053061, default to 51052325"
        hanapackage="51052325"
      fi
    fi
  fi
fi



mkdir /etc/systemd/login.conf.d
mkdir /hana
mkdir /hana/data
mkdir /hana/log
mkdir /hana/shared
mkdir /hana/backup
mkdir /usr/sap

# this assumes that 5 disks are attached at lun 0 through 4
echo "Creating partitions and physical volumes"
pvcreate -ff -y /dev/disk/azure/scsi1/lun0   
pvcreate -ff -y  /dev/disk/azure/scsi1/lun1
pvcreate -ff -y  /dev/disk/azure/scsi1/lun2
pvcreate -ff -y  /dev/disk/azure/scsi1/lun3
pvcreate -ff -y  /dev/disk/azure/scsi1/lun4
pvcreate -ff -y  /dev/disk/azure/scsi1/lun5
pvcreate -ff -y  /dev/disk/azure/scsi1/lun6
pvcreate -ff -y  /dev/disk/azure/scsi1/lun7

#in the following, default to xfs
FSTYPE="xfs"

if [ $VMSIZE == "Standard_E8s_v3" ] || [ $VMSIZE == "Standard_E16s_v3" ] || [ "$VMSIZE" == "Standard_E32s_v3" ] || [ "$VMSIZE" == "Standard_E64s_v3" ] || [ "$VMSIZE" == "Standard_GS5" ] || [ "$VMSIZE" == "Standard_M32ts" ] || [ "$VMSIZE" == "Standard_M32ls" ] || [ "$VMSIZE" == "Standard_M64ls" ] || [ $VMSIZE == "Standard_DS14_v2" ] ; then
echo "logicalvols start" >> /tmp/parameter.txt

#shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate sharedvg $sharedvglun
  lvcreate -l 100%FREE -n sharedlv sharedvg 
 
#usr volume creation
  usrsapvglun="/dev/disk/azure/scsi1/lun1"
  vgcreate usrsapvg $usrsapvglun
  lvcreate -l 100%FREE -n usrsaplv usrsapvg

#backup volume creation
  backupvglun="/dev/disk/azure/scsi1/lun2"
  vgcreate backupvg $backupvglun
  lvcreate -l 100%FREE -n backuplv backupvg 

#data volume creation
  datavg1lun="/dev/disk/azure/scsi1/lun3"
  datavg2lun="/dev/disk/azure/scsi1/lun4"
  datavg3lun="/dev/disk/azure/scsi1/lun5"
  vgcreate datavg $datavg1lun $datavg2lun $datavg3lun
  PHYSVOLUMES=3
  STRIPESIZE=64
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n datalv datavg

#log volume creation
  logvg1lun="/dev/disk/azure/scsi1/lun6"
  logvg2lun="/dev/disk/azure/scsi1/lun7"
  vgcreate logvg $logvg1lun $logvg2lun
  PHYSVOLUMES=2
  STRIPESIZE=32
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n loglv logvg



  mkfs.$FSTYPE /dev/datavg/datalv
  mkfs.$FSTYPE /dev/logvg/loglv
  mkfs -t $FSTYPE /dev/sharedvg/sharedlv 
  mkfs -t $FSTYPE /dev/backupvg/backuplv 
  mkfs -t $FSTYPE /dev/usrsapvg/usrsaplv
echo "logicalvols end" >> /tmp/parameter.txt
fi

if [ $VMSIZE == "Standard_M64s" ]; then

# this assumes that 6 disks are attached at lun 0 through 5
echo "Creating partitions and physical volumes"
pvcreate -ff -y /dev/disk/azure/scsi1/lun8
pvcreate -ff -y /dev/disk/azure/scsi1/lun9

echo "logicalvols start" >> /tmp/parameter.txt
#shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate sharedvg $sharedvglun
  lvcreate -l 100%FREE -n sharedlv sharedvg 
 
#usr volume creation
  usrsapvglun="/dev/disk/azure/scsi1/lun1"
  vgcreate usrsapvg $usrsapvglun
  lvcreate -l 100%FREE -n usrsaplv usrsapvg

#backup volume creation
  backupvg1lun="/dev/disk/azure/scsi1/lun2"
  backupvg2lun="/dev/disk/azure/scsi1/lun3"
  vgcreate backupvg $backupvg1lun $backupvg2lun
  lvcreate -l 100%FREE -n backuplv backupvg 

#data volume creation
  datavg1lun="/dev/disk/azure/scsi1/lun4"
  datavg2lun="/dev/disk/azure/scsi1/lun5"
  datavg3lun="/dev/disk/azure/scsi1/lun6"
  datavg4lun="/dev/disk/azure/scsi1/lun7"
  vgcreate datavg $datavg1lun $datavg2lun $datavg3lun $datavg4lun
  PHYSVOLUMES=4
  STRIPESIZE=64
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n datalv datavg

#log volume creation
  logvg1lun="/dev/disk/azure/scsi1/lun8"
  logvg2lun="/dev/disk/azure/scsi1/lun9"
  vgcreate logvg $logvg1lun $logvg2lun
  PHYSVOLUMES=2
  STRIPESIZE=32
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n loglv logvg


  mkfs.$FSTYPE /dev/datavg/datalv
  mkfs.$FSTYPE /dev/logvg/loglv
  mkfs -t $FSTYPE /dev/sharedvg/sharedlv 
  mkfs -t $FSTYPE /dev/backupvg/backuplv 
  mkfs -t $FSTYPE /dev/usrsapvg/usrsaplv
echo "logicalvols end" >> /tmp/parameter.txt
fi

if [ $VMSIZE == "Standard_M64ms" ] || [ $VMSIZE == "Standard_M128s" ]  ; then

# this assumes that 6 disks are attached at lun 0 through 9
echo "Creating partitions and physical volumes"
pvcreate  -ff -y /dev/disk/azure/scsi1/lun8

echo "logicalvols start" >> /tmp/parameter.txt
#shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate sharedvg $sharedvglun
  lvcreate -l 100%FREE -n sharedlv sharedvg 
 
#usr volume creation
  usrsapvglun="/dev/disk/azure/scsi1/lun1"
  vgcreate usrsapvg $usrsapvglun
  lvcreate -l 100%FREE -n usrsaplv usrsapvg

#backup volume creation
  backupvg1lun="/dev/disk/azure/scsi1/lun2"
  backupvg2lun="/dev/disk/azure/scsi1/lun3"
  vgcreate backupvg $backupvg1lun $backupvg2lun
  lvcreate -l 100%FREE -n backuplv backupvg 

#data volume creation
  datavg1lun="/dev/disk/azure/scsi1/lun4"
  datavg2lun="/dev/disk/azure/scsi1/lun5"
  datavg3lun="/dev/disk/azure/scsi1/lun6"
  vgcreate datavg $datavg1lun $datavg2lun $datavg3lun 
  PHYSVOLUMES=3
  STRIPESIZE=64
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n datalv datavg

#log volume creation
  logvg1lun="/dev/disk/azure/scsi1/lun7"
  logvg2lun="/dev/disk/azure/scsi1/lun8"
  vgcreate logvg $logvg1lun $logvg2lun
  PHYSVOLUMES=2
  STRIPESIZE=32
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n loglv logvg


  mkfs.$FSTYPE /dev/datavg/datalv
  mkfs.$FSTYPE /dev/logvg/loglv
  mkfs -t $FSTYPE /dev/sharedvg/sharedlv 
  mkfs -t $FSTYPE /dev/backupvg/backuplv 
  mkfs -t $FSTYPE /dev/usrsapvg/usrsaplv
echo "logicalvols end" >> /tmp/parameter.txt
fi

if [ $VMSIZE == "Standard_M128ms" ] ||  [ $VMSIZE == "Standard_M208ms_v2" ] ||  [ $VMSIZE == "Standard_M416ms_v2" ] ; then
FSTYPE="ext3"
# this assumes that 6 disks are attached at lun 0 through 5
echo "Creating partitions and physical volumes"
pvcreate  -ff -y /dev/disk/azure/scsi1/lun8
pvcreate  -ff -y /dev/disk/azure/scsi1/lun9
pvcreate  -ff -y /dev/disk/azure/scsi1/lun10

echo "logicalvols start" >> /tmp/parameter.txt
#shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate sharedvg $sharedvglun
  lvcreate -l 100%FREE -n sharedlv sharedvg 
 
#usr volume creation
  usrsapvglun="/dev/disk/azure/scsi1/lun1"
  vgcreate usrsapvg $usrsapvglun
  lvcreate -l 100%FREE -n usrsaplv usrsapvg

#backup volume creation
  backupvg1lun="/dev/disk/azure/scsi1/lun2"
  backupvg2lun="/dev/disk/azure/scsi1/lun3"
  vgcreate backupvg $backupvg1lun $backupvg2lun
  lvcreate -l 100%FREE -n backuplv backupvg 

#data volume creation
  datavg1lun="/dev/disk/azure/scsi1/lun4"
  datavg2lun="/dev/disk/azure/scsi1/lun5"
  datavg3lun="/dev/disk/azure/scsi1/lun6"
  datavg4lun="/dev/disk/azure/scsi1/lun7"
  datavg5lun="/dev/disk/azure/scsi1/lun8"
  vgcreate datavg $datavg1lun $datavg2lun $datavg3lun $datavg4lun $datavg5lun
  PHYSVOLUMES=4
  STRIPESIZE=64
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n datalv datavg

#log volume creation
  logvg1lun="/dev/disk/azure/scsi1/lun9"
  logvg2lun="/dev/disk/azure/scsi1/lun10"
  vgcreate logvg $logvg1lun $logvg2lun
  PHYSVOLUMES=2
  STRIPESIZE=32
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n loglv logvg

  #change to ext3 due to bug
  mkfs.$FSTYPE /dev/datavg/datalv
  mkfs.$FSTYPE /dev/logvg/loglv
  mkfs -t $FSTYPE /dev/sharedvg/sharedlv 
  mkfs -t $FSTYPE /dev/backupvg/backuplv 
  mkfs -t $FSTYPE /dev/usrsapvg/usrsaplv
fi
#!/bin/bash
echo "mounthanashared start" >> /tmp/parameter.txt
mount -t $FSTYPE /dev/sharedvg/sharedlv /hana/shared
mount -t $FSTYPE /dev/backupvg/backuplv /hana/backup 
mount -t $FSTYPE /dev/usrsapvg/usrsaplv /usr/sap
mount -t $FSTYPE /dev/datavg/datalv /hana/data
mount -t $FSTYPE /dev/logvg/loglv /hana/log 
echo "mounthanashared end" >> /tmp/parameter.txt

echo "write to fstab start" >> /tmp/parameter.txt
echo "/dev/mapper/datavg-datalv /hana/data $FSTYPE defaults 0 0" >> /etc/fstab
echo "/dev/mapper/logvg-loglv /hana/log $FSTYPE defaults 0 0" >> /etc/fstab
echo "/dev/mapper/sharedvg-sharedlv /hana/shared $FSTYPE defaults 0 0" >> /etc/fstab
echo "/dev/mapper/backupvg-backuplv /hana/backup $FSTYPE defaults 0 0" >> /etc/fstab
echo "/dev/mapper/usrsapvg-usrsaplv /usr/sap $FSTYPE defaults 0 0" >> /etc/fstab
echo "write to fstab end" >> /tmp/parameter.txt

cat >>/etc/hosts <<EOF
$VMIPADDR $VMNAME
$OTHERIPADDR $OTHERVMNAME
EOF

if [ "$NFSIP" != "" ]; then
cat >>/etc/hosts <<EOF
$NFSIP nfsnfslb
EOF

fi


if [ "$NFSIP" != "" ]; then
  mkdir /sapbits
  mount -t nfs4 nfsnfslb:/NWS/SapBits /sapbits
  RESULT=$?
  ##if the mount of sapbits fails, use the local volume instead.
  ##
  if [ "$RESULT" != "0" ]; then
    mkdir /hana/data/sapbits
    SAPBITSDIR="/hana/data/sapbits"
    rmdir /sapbits
    ln -s  /hana/data/sapbits /sapbits
    NFSIP=""
  else
    echo "nfsnfslb:/NWS/SapBits /sapbits nfs4 defaults 0 0" >> /etc/fstab
    SAPBITSDIR="/sapbits"
  fi
else
  mkdir /hana/data/sapbits
  SAPBITSDIR="/hana/data/sapbits"
  ln -s  /hana/data/sapbits /sapbits
fi

#install hana prereqs
retry 5 "zypper install -y glibc-2.22-51.6"
retry 5 "zypper install -y systemd-228-142.1"
retry 5 "zypper install -y unrar"
retry 5 "zypper in -t pattern -y sap-hana"
#zypper install -y sapconf
retry 5 "zypper install -y saptune"
retry 5 "zypper install -y libunwind"
retry 5 "zypper install -y libicu"

saptune solution apply HANA
saptune daemon start

# step2
echo $URI >> /tmp/url.txt

cp -f /etc/waagent.conf /etc/waagent.conf.orig
sedcmd="s/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g"
sedcmd2="s/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=16384/g"
cat /etc/waagent.conf | sed $sedcmd | sed $sedcmd2 > /etc/waagent.conf.new
cp -f /etc/waagent.conf.new /etc/waagent.conf
# we may be able to restart the waagent and get the swap configured immediately


#!/bin/bash
cd $SAPBITSDIR
echo "hana download start" >> /tmp/parameter.txt
if [ "${hanapackage}" = "51053787" ]
then 
  download_if_needed $SAPBITSDIR "$URI/SapBits" "${hanapackage}.ZIP"
  cd $SAPBITSDIR
  mkdir ${hanapackage}
  cd ${hanapackage}
  unzip -o ../${hanapackage}.ZIP
  cd $SAPBITSDIR
  #add additional requirement
  zypper install -y libatomic1
else

  download_if_needed $SAPBITSDIR "$URI/SapBits" "${hanapackage}_part1.exe"
  download_if_needed $SAPBITSDIR "$URI/SapBits" "${hanapackage}_part2.rar"  
  download_if_needed $SAPBITSDIR "$URI/SapBits" "${hanapackage}_part3.rar"  
  download_if_needed $SAPBITSDIR "$URI/SapBits" "${hanapackage}_part4.rar"  
  cd $SAPBITSDIR

  echo "hana unrar start" >> /tmp/parameter.txt
  #!/bin/bash
  cd $SAPBITSDIR
  unrar  -o- x ${hanapackage}_part1.exe
  echo "hana unrar end" >> /tmp/parameter.txt

fi

cd $SAPBITSDIR
#retrieve config file.  first try on download location, then go to our repo
/usr/bin/wget --quiet $URI/SapBits/hdbinst.cfg
rc=$?;
if [[ $rc != 0 ]];
then
retry 5 "/usr/bin/wget --quiet https://raw.githubusercontent.com/AzureCAT-GSI/Hana-Test-Deploy/master/hdbinst.cfg"
fi

echo "hana download end" >> /tmp/parameter.txt

date >> /tmp/testdate

echo "hana prepare start" >> /tmp/parameter.txt
cd $SAPBITSDIR

#!/bin/bash
cd $SAPBITSDIR
myhost=`hostname`
sedcmd="s/REPLACE-WITH-HOSTNAME/$myhost/g"
if [ "$NFSIP" != "" ]; then
 sedcmd2="s/\/hana\/shared\/sapbits\/51052325/\/sapbits\/${hanapackage}/g"
else
 sedcmd2="s/\/hana\/shared\/sapbits\/51052325/\/hana\/data\/sapbits\/${hanapackage}/g"
fi

sedcmd3="s/root_user=root/root_user=$HANAUSR/g"
sedcmd4="s/root_password=AweS0me@PW/root_password=$HANAPWD/g"
sedcmd5="s/master_password=AweS0me@PW/master_password=$HANAPWD/g"
sedcmd6="s/sid=H10/sid=$HANASID/g"
sedcmd7="s/number=00/number=$HANANUMBER/g"
hdbinstfile="${SAPBITSDIR}/hdbinst-${myhost}.cfg"
cat hdbinst.cfg | sed $sedcmd | sed $sedcmd2 | sed $sedcmd3 | sed $sedcmd4 | sed $sedcmd5 | sed $sedcmd6 > ${hdbinstfile}
echo "hana preapre end" >> /tmp/parameter.txt

##change this to pass passwords on command line

#!/bin/bash
echo "install hana start" >> /tmp/parameter.txt
cd $SAPBITSDIR/${hanapackage}/DATA_UNITS/HDB_LCM_LINUX_X86_64
$SAPBITSDIR/${hanapackage}/DATA_UNITS/HDB_LCM_LINUX_X86_64/hdblcm -b --configfile ${hdbinstfile}
echo "install hana end" >> /tmp/parameter.txt
echo "install hana end" >> /tmp/hanacomplete.txt

##external dependency on sshpt
    retry 5 "zypper --non-interactive --no-gpg-checks addrepo https://download.opensuse.org/repositories/openSUSE:/Tools/SLE_12_SP3/openSUSE:Tools.repo"
    retry 5 "zypper --non-interactive --no-gpg-checks refresh"
    retry 5 "zypper install -y python-pip"
    retry 5 "pip install sshpt==1.3.11"
    #set up passwordless ssh on both sides
    cd ~/
    #rm -r -f .ssh
    cat /dev/zero |ssh-keygen -q -N "" > /dev/null

    sshpt --hosts $OTHERVMNAME -u $HANAUSR -p $HANAPWD --sudo "mkdir -p /root/.ssh"
    sshpt --hosts $OTHERVMNAME -u $HANAUSR -p $HANAPWD --sudo -c ~/.ssh/id_rsa.pub -d /root/
    sshpt --hosts $OTHERVMNAME -u $HANAUSR -p $HANAPWD --sudo "cp /root/id_rsa.pub /root/.ssh/authorized_keys"
    sshpt --hosts $OTHERVMNAME -u $HANAUSR -p $HANAPWD --sudo "chmod 700 /root/.ssh"
    sshpt --hosts $OTHERVMNAME -u $HANAUSR -p $HANAPWD --sudo "chown root:root /root/.ssh/authorized_keys"
    sshpt --hosts $OTHERVMNAME -u $HANAUSR -p $HANAPWD --sudo "chmod 700 /root/.ssh/authorized_keys"
    
#
if [ "$CONFIGHSR" == "yes" ]; then
    echo "hsr config start" >> /tmp/parameter.txt	    
    HANASIDU="${HANASID^^}"

    cd /root
    SYNCUSER="hsrsync"
    SYNCPASSWORD="Repl1cate"

 ##get rid of user creation, was only needed in hana 1.0   
 ##remove the "initial backup" because it's redundant
    cat >/tmp/hdbsetupsql <<EOF
CREATE USER $SYNCUSER PASSWORD $SYNCPASSWORD;
grant data admin to $SYNCUSER;
ALTER USER $SYNCUSER DISABLE PASSWORD LIFETIME;
backup data using file ('initial backup'); 
BACKUP DATA for $HANASID USING FILE ('backup');
BACKUP DATA for SYSTEMDB USING FILE ('SYSTEMDB backup');
EOF


chmod a+r /tmp/hdbsetupsql
su - -c "hdbsql -u system -p $HANAPWD -d SYSTEMDB -I /tmp/hdbsetupsql" $HANAADMIN 
touch /tmp/hanabackupdone.txt
waitfor root $OTHERVMNAME /tmp/hanabackupdone.txt

    
if [ "$ISPRIMARY" = "yes" ]; then
	echo "hsr primary start" >> /tmp/parameter.txt	

	#now set the role on the primary
	cat >/tmp/srenable <<EOF
hdbnsutil -sr_enable --name=system0 	
EOF
	chmod a+r /tmp/srenable
	su - $HANAADMIN -c "bash /tmp/srenable"

	touch /tmp/readyforsecondary.txt
	waitfor root $OTHERVMNAME /tmp/readyforcerts.txt	
	scp /usr/sap/$HANASIDU/SYS/global/security/rsecssfs/data/SSFS_$HANASIDU.DAT root@$OTHERVMNAME:/root/SSFS_$HANASIDU.DAT
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@$OTHERVMNAME "cp /root/SSFS_$HANASIDU.DAT /usr/sap/$HANASIDU/SYS/global/security/rsecssfs/data/SSFS_$HANASIDU.DAT"
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@$OTHERVMNAME "chown $HANAADMIN:sapsys /usr/sap/$HANASIDU/SYS/global/security/rsecssfs/data/SSFS_$HANASIDU.DAT"

	scp /usr/sap/$HANASIDU/SYS/global/security/rsecssfs/key/SSFS_$HANASIDU.KEY root@$OTHERVMNAME:/root/SSFS_$HANASIDU.KEY
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@$OTHERVMNAME "cp /root/SSFS_$HANASIDU.KEY /usr/sap/$HANASIDU/SYS/global/security/rsecssfs/key/SSFS_$HANASIDU.KEY"
	ssh -o BatchMode=yes  -o StrictHostKeyChecking=no root@$OTHERVMNAME "chown $HANAADMIN:sapsys /usr/sap/$HANASIDU/SYS/global/security/rsecssfs/key/SSFS_$HANASIDU.KEY"

	touch /tmp/dohsrjoin.txt
    else
	#do stuff on the secondary
	waitfor root $OTHERVMNAME /tmp/readyforsecondary.txt	

	touch /tmp/readyforcerts.txt
	waitfor root $OTHERVMNAME /tmp/dohsrjoin.txt	
	cat >/tmp/hsrjoin <<EOF
sapcontrol -nr $HANANUMBER -function StopSystem HDB
sapcontrol -nr $HANANUMBER -function WaitforStopped 600 2
hdbnsutil -sr_register --name=system1 --remoteHost=$OTHERVMNAME --remoteInstance=$HANANUMBER --replicationMode=sync --operationMode=logreplay
sapcontrol -nr $HANANUMBER -function StartSystem HDB
EOF

	chmod a+r /tmp/hsrjoin
	su - $HANAADMIN -c "bash /tmp/hsrjoin"
    fi
fi

#Clustering setup
#start services [A]
systemctl enable iscsid
systemctl enable iscsi
systemctl enable sbd

#set up iscsi initiator [A]
myhost=`hostname`
cp -f /etc/iscsi/initiatorname.iscsi /etc/iscsi/initiatorname.iscsi.orig
#change the IQN to the iscsi server
sed -i "/InitiatorName=/d" "/etc/iscsi/initiatorname.iscsi"
echo "InitiatorName=$IQNCLIENT" >> /etc/iscsi/initiatorname.iscsi
systemctl restart iscsid
systemctl restart iscsi
retry 5 "iscsiadm -m discovery --type=st --portal=$ISCSIIP"

retry 5 "iscsiadm -m node -T $IQN --login --portal=$ISCSIIP:3260"
retry 5 "iscsiadm -m node -p $ISCSIIP:3260 --op=update --name=node.startup --value=automatic"

#node1
if [ "$ISPRIMARY" = "yes" ]; then

sleep 10 
echo "hana iscsi end" >> /tmp/parameter.txt

device="$(lsscsi 6 0 0 0| cut -c59-)"
diskid="$(ls -l /dev/disk/by-id/scsi-* | grep $device)"
sbdid="$(echo $diskid | grep -o -P '/dev/disk/by-id/scsi-3.{32}')"

sbd -d $sbdid -1 ${WATCHDOGTIMEOUT} -4 ${MSGWAITTIMEOUT} create
else

echo "hana iscsi end" >> /tmp/parameter.txt
sleep 10 
fi

#!/bin/bash [A]
cd /etc/sysconfig
cp -f /etc/sysconfig/sbd /etc/sysconfig/sbd.new
device="$(lsscsi 6 0 0 0| cut -c59-)"
diskid="$(ls -l /dev/disk/by-id/scsi-* | grep $device)"
sbdid="$(echo $diskid | grep -o -P '/dev/disk/by-id/scsi-3.{32}')"

sbdcmd="s#SBD_DEVICE=\"\"SBD_DEVICE=\"$sbdid\"#g"
sbdcmd2='s/SBD_PACEMAKER=.*/SBD_PACEMAKER="yes"/g'
sbdcmd3='s/SBD_STARTMODE=.*/SBD_STARTMODE="always"/g'
cat sbd.new | sed $sbdcmd | sed $sbdcmd2 | sed $sbdcmd3 > /etc/sysconfig/sbd.modified
echo "SBD_WATCHDOG=yes" >>/etc/sysconfigsbd.modified
cp -f /etc/sysconfig/sbd.modified /etc/sysconfig/sbd
echo "hana sbd end" >> /tmp/parameter.txt


echo softdog > /etc/modules-load.d/softdog.conf
modprobe -v softdog
echo "hana watchdog end" >> /tmp/parameter.txt
cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

setup_cluster $ISPRIMARY $sbdid $VMNAME $OTHERVMNAME "hanacluster"

#node1
if [ "$ISPRIMARY" = "yes" ]; then
#configure SAP HANA topology
HANAID="$HANASID"_HDB"$HANANUMBER"

crm configure property maintenance-mode=true

crm configure delete stonith-sbd

crm configure primitive stonith-sbd stonith:external/sbd \
     params pcmk_delay_max="15" \
     op monitor interval="15" timeout="15"


crm configure property \$id="cib-bootstrap-options" stonith-enabled=true \
               no-quorum-policy="ignore" \
               stonith-action="reboot" \
               stonith-timeout=$STONITHTIMEOUT

crm configure  rsc_defaults \$id="rsc-options"  resource-stickiness="1000" migration-threshold="5000"


crm configure  op_defaults \$id="op-options"  timeout="600"

crm configure primitive rsc_SAPHanaTopology_$HANAID ocf:suse:SAPHanaTopology \
        operations \$id="rsc_sap2_$HANAID-operations" \
        op monitor interval="10" timeout="600" \
        op start interval="0" timeout="600" \
        op stop interval="0" timeout="300" \
        params SID="$HANASID" InstanceNumber="$HANANUMBER"

crm configure clone cln_SAPHanaTopology_$HANAID rsc_SAPHanaTopology_$HANAID \
        meta clone-node-max="1" interleave="true"


crm configure primitive rsc_SAPHana_$HANAID ocf:suse:SAPHana     \
operations \$id="rsc_sap_$HANAID-operations"   \
op start interval="0" timeout="3600"    \
op stop interval="0" timeout="3600"    \
op promote interval="0" timeout="3600"    \
op monitor interval="60" role="Master" timeout="700"    \
op monitor interval="61" role="Slave" timeout="700"   \
params SID="$HANASID" InstanceNumber="$HANANUMBER" PREFER_SITE_TAKEOVER="true"  \
DUPLICATE_PRIMARY_TIMEOUT="7200" AUTOMATED_REGISTER="false"

crm configure ms msl_SAPHana_$HANAID rsc_SAPHana_$HANAID meta is-managed="true" \
notify="true" clone-max="2" clone-node-max="1" target-role="Started" interleave="true"

crm configure primitive rsc_ip_$HANAID ocf:heartbeat:IPaddr2 \
        operations \$id="rsc_ip_$HANAID-operations" \
        op monitor interval="10s" timeout="20s" \
        params ip="$LBIP"

crm configure primitive rsc_nc_$HANAID anything \
     params binfile="/usr/bin/nc" cmdline_options="-l -k 62503" \
     op monitor timeout=20s interval=10 depth=0

crm configure group g_ip_$HANAID rsc_ip_$HANAID rsc_nc_$HANAID

#crm configure colocation col_saphana_ip_$HANAID 2000: rsc_ip_$HANAID:Started \
#    msl_SAPHana_$HANAID:Master
crm configure colocation col_saphana_ip_$HANAID 4000: g_ip_$HANAID:Started  msl_SAPHana_$HANAID:Master

crm configure order ord_SAPHana_$HANAID Optional: cln_SAPHanaTopology_$HANAID  msl_SAPHana_$HANAID

sleep 20

crm resource cleanup rsc_SAPHana_$HANAID

crm configure property maintenance-mode=false

fi

echo "software deploy completed.  Please check for proper software install"



#!/bin/bash
set -e

start_time=$(date +"%s")

SOURCES_LIST="sources_list"
TESTBED="testbed.py"
CONTRAIL_PKG=""
INSTALL_SM_LITE="install_sm_lite"
CLEANUP_PUPPET_AGENT=""

function usage()
{
    echo "Usage"
    echo ""
    echo "$0"
    echo -e "\t-h --help"
    echo -e "\t-c|--contrail-package <pkg>"
    echo -e "\t-t|--testbed <testbed.py>"
    echo -e "\t-ns|--no-sources-list"
    echo -e  "\t-ni|--no-install-sm-lite"
    echo -e "\t-cp|--cleanup-puppet-agent"
    echo ""
}

if [ "$#" -eq 0 ]; then
   usage
   exit
fi

while [[ $# > 0 ]]
do
key="$1"

case $key in
    -c|--contrail-package)
    CONTRAIL_PKG="$2"
    shift # past argument
    ;;
    -t|--testbed)
    TESTBED="$2"
    shift # past argument
    ;;
    -ns|--no-sources-list)
    SOURCES_LIST=""
    ;;
    -ni|--no-install-sm-lite)
    INSTALL_SM_LITE=""
    ;;
    -cp|--no-cleanup-puppet-agent)
    CLEANUP_PUPPET_AGENT="cleanup_puppet_agent"
    ;;
    -h|--help)
    usage
    exit
    ;;
    *)
            # unknown option
    echo "ERROR: unknown parameter $key"
    usage
    exit 1
    ;;
esac
shift # past argument or value
done


if [ "$TESTBED" == "" ] || [ "$CONTRAIL_PKG" == "" ]; then
   exit
fi

function setup_source_list_for_internet()
{
   # Copy sources.list to point to internet repos
   rel=`lsb_release -r`
   rel=( $rel )
   cp /etc/apt/sources.list /etc/apt/sources.list.$(date +%Y_%m_%d__%H_%M_%S).contrailbackup
   if [ ${rel[1]} == "14.04"  ]; then
      cp /opt/contrail/contrail_server_manager/ubuntu_14_04_1_sources.list /etc/apt/sources.list
   else
      cp /opt/contrail/contrail_server_manager/ubuntu_12_04_3_sources.list /etc/apt/sources.list
   fi
   apt-get update
}

function cleanup_puppet_agent()
{
   apt-get -y --purge autoremove puppet puppet-common hiera
   rm -rf /etc/puppet /var/lib/puppet
}

# Copy sources list from the installer repo
if [ "$SOURCES_LIST" != "" ]; then
   echo "Use the sources.list from installer package"
   setup_source_list_for_internet
fi

if [ "$CLEANUP_PUPPET_AGENT" != "" ]; then
   echo "--> Remove puppet agent, if it is present"
   cleanup_puppet_agent
fi

# Install sever manager 
if [ "$INSTALL_SM_LITE" != "" ]; then
    echo "--> Install server manager lite"
   /opt/contrail/contrail_server_manager/setup.sh --all --smlite --nowebui --nosm-mon
fi 

echo "--> Convert testbed.py to server manager entities"
# Convert testbed.py to server manager object json files
/opt/contrail/server_manager/client/testbed_parser.py --testbed ${TESTBED} --contrail-packages ${CONTRAIL_PKG}

echo "--> Pre provision checks to make sure setup is ready for contrail provisioning"
# Precheck the targets to make sure that, ready for contrail provisioning
SERVER_MGR_IP=$(grep listen_ip_addr /opt/contrail/server_manager/sm-config.ini | grep -Po "listen_ip_addr = \K.*")
/opt/contrail/server_manager/client/preconfig.py --server-json server.json --server-manager-ip ${SERVER_MGR_IP}

echo "--> Adding server manager objects to server manager database"
# Create package, cluster, server objects
server-manager add image -f image.json 
server-manager add cluster -f cluster.json 
server-manager add server -f server.json 

echo "--> Provisioning the cluster"
# Provision the cluster
CONTRAIL_PKG_ID=$(python -c "import json; fid = open('image.json', 'r'); contents = fid.read(); cjson = json.loads(contents); print cjson['image'][0]['id']")
server-manager provision -F --cluster_id cluster ${CONTRAIL_PKG_ID} 

end_time=$(date +"%s")
diff=$(($end_time-$start_time))
echo "--> Provisioning is issued, and took $(($diff / 60)) minutes and $(($diff % 60)) seconds."
echo "--> Check provisioning status using provision_status.sh"

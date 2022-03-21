#!/bin/bash
#set -x

############################################################################################
##
## Script to install Zscaler Client Connector to macOS Devices 
##
###########################################
## Based of https://github.com/microsoft/shell-intune-samples/blob/master/Apps/Visual%20Studio%20Code/installVSCode.sh
## Based of https://emm.how/t/deploying-zscaler-on-macos-with-intune/1363
## Modified by Simon Goltz - https://simongoltz.com

# Define variables

cloudName="" #Your ZIA Cloud Name without TLD? zscloud.net = zscloud zscaler.net = zscaler
userDomain="" #Your Sign in Domain, multiple domains may need multiple scripts
weburl="https://***.cloudfront.net/...-installer.app.zip" #Retreive latest version from Zscaler Portal

tempfile="/tmp/zscaler/zscaler.zip"
appname="Zscaler"
appfile="Zscaler.app"
log="/var/log/installzscaler.log"
autoUpdate="true"


## Is the app already installed?
if [ -d "/Applications/$appname/$appfile" ]; then

    # App is installed, if it's updates are handled by MAU we should quietly exit
    if [[ $autoUpdate == "true" ]]; then
        echo "$(date) | [$appname] is already installed and handles updates itself, exiting"
        exit 0
    fi
fi

waitForCurl () {
    while ps aux | grep curl | grep -v grep; do
        echo "$(date) | Another instance of Curl is running, waiting 60s for it to complete"
        sleep 60
    done
    echo "$(date) | No Curl's running, let's start our download"
}

# start logging
exec 1>> $log 2>&1

# Begin Script Body
echo ""
echo "##############################################################"
echo "# $(date) | Starting install of $appname"
echo "############################################################"
echo ""

rm -rf /tmp/zscaler
mkdir /tmp/zscaler

echo "$(date) | Downloading $appname"
waitForCurl
curl -L -f -o $tempfile $weburl

cd /tmp/zscaler
echo "$(date) | Unzipping $tempfile"
unzip -q $tempfile > /dev/null
app=$(ls -1 /tmp/zscaler/ | grep .app | head -1)

echo "$(date) | Executing installbuilder.sh from ${app}"
sudo sh "/tmp/zscaler/${app}/Contents/MacOS/installbuilder.sh" --hideAppUIOnLaunch 1 --mode unattended --unattendedmodeui none --cloudName $cloudName --userDomain $userDomain

echo "$(date) | Cleaning up tmp files"
rm -rf "/tmp/zscaler"
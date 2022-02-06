#!/bin/bash

# --------------------------------------------------------

# WARNING! THIS SCRIPT WILL DESTROY AN NGINX/OPENRESTY
# SERVER. ONLY USE IT IF YOU WANT TO UNDO THE 
# INSTALLATION PERFORMED BY install_openresty.sh

# I AM NOT RESPONSIBLE IF YOU SCREW UP YOUR NGINX SERVER

# --------------------------------------------------------

read -p "This will completely destroy your OpenResty server. Are you sure you want to continue? [y/n]" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Aborting uninstall script"
    exit 1
else
    echo "Proceeding with uninstall"
fi

export OPENRESTY_INSTALL_PATH=/usr/local/openresty
export GEOIP2_DB_PATH=/usr/local/etc/geoip2
export MODSECURITY_PATH=/usr/local/modsecurity
export MODSECURITY_CRS_PATH=/usr/local/modsecurity-crs
export SERVICE_FILE=/etc/systemd/system/openresty.service

# Stop and remove the service
sudo systemctl stop openresty
sudo systemctl disable openresty
sudo rm $SERVICE_FILE

# Remove files
sudo rm -rf $OPENRESTY_INSTALL_PATH
sudo rm -rf $GEOIP2_DB_PATH
sudo rm -rf $MODSECURITY_PATH
sudo rm -rf $MODSECURITY_CRS_PATH

# Remove secure_paths override
export SECURE_PATHS_FILE=/etc/sudoers.d/secure_path_override
sudo rm $SECURE_PATHS_FILE

# Uninstall acme.sh
sudo acme.sh --uninstall

# DONE
echo "SCRIPT COMPLETE!"
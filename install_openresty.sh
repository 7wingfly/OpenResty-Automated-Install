#!/bin/bash

# -----------------------------------------------------

# WARNING! DO NOT RUN THIS SCRIPT ON A SERVER 
# ALREADY RUNNING AN INSTALLATION OF NGINX OR
# OPENRESTY. IT IS INTENDED FOR FRESH INSTALLS
# OF UBUNTU ONLY. I AM NOT RESPONSIBLE IF YOU
# SCREW UP AN EXISTING NGINX SERVER WITH THIS
# SCRIPT.

# This script will download and install OpenResty
# along with the GeoIP2 & ModSecurity WAF modules,
# the ModSecurity application, MaxMind GeoLite2 
# databases and the ACME.sh tool for creating certs. 

# It will also configure nginx.conf to import GeoIP2 
# and ModSecurity modules, add the GeoIP2 databases.

# This script will take around 25 minutes to complete 
# if you're running it for first the time. This is
# mostly due to the time it takes to compile 
# ModSecurity.

# Creted by Benjamin Watkins Feb 2022.
# watkins.ben@gmail.com

# -----------------------------------------------------

# Prevent sudo from timing out
sudo -v
while true; do  
  sudo -nv; sleep 1m
  kill -0 $$ 2>/dev/null || exit
done &

export OPENRESTY_VERSION=1.19.9.1
export OPENRESTY_BUILD_PATH=~/openrestysetup
export OPENRESTY_INSTALL_PATH=/usr/local/openresty
export GEOIP2_DB_PATH=/usr/local/etc/geoip2
export MODSECURITY_BUILD_PATH=$OPENRESTY_BUILD_PATH/ModSecurity

# Clean up old setup files if present
sudo rm -rf $OPENRESTY_BUILD_PATH

# Create folder structure
mkdir $OPENRESTY_BUILD_PATH/modules -p
sudo mkdir $GEOIP2_DB_PATH

cd $OPENRESTY_BUILD_PATH

# Download and install OpenResty prerequisites
sudo apt update
sudo apt -y install libpcre3-dev libssl-dev perl make build-essential curl acl
sudo wget https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz $OPENRESTY_BUILD_PATH

# Download and install prerequisites for GeoIP2
sudo add-apt-repository ppa:maxmind/ppa -y
sudo apt update
sudo apt -y install libmaxminddb0 libmaxminddb-dev mmdb-bin libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev

# Download GeoLite2 databases for GeopIP2 module
sudo wget https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb -O $GEOIP2_DB_PATH/GeoLite2-City.mmdb
sudo wget https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb -O $GEOIP2_DB_PATH/GeoLite2-Country.mmdb

# GeoIP2 Module
sudo wget https://github.com/leev/ngx_http_geoip2_module/archive/refs/tags/3.3.tar.gz -P $OPENRESTY_BUILD_PATH/modules
sudo tar -xvf ./modules/3.3.tar.gz -C $OPENRESTY_BUILD_PATH/modules

# ModSecurity-Nginx Connector Module
sudo git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git $OPENRESTY_BUILD_PATH/modules/ngx_mod_security

# Install ModSecurity
if [ ! -d "/usr/local/modsecurity" ]; then    
    sudo apt-get -y install bison build-essential ca-certificates curl dh-autoreconf doxygen flex gawk git iputils-ping libcurl4-gnutls-dev libexpat1-dev libgeoip-dev liblmdb-dev libpcre3-dev libpcre++-dev libssl-dev libtool libxml2 libxml2-dev libyajl-dev locales lua5.3-dev pkg-config wget zlib1g-dev zlibc libgd-dev git
    sudo rm -rf $MODSECURITY_BUILD_PATH
    sudo git clone https://github.com/SpiderLabs/ModSecurity $MODSECURITY_BUILD_PATH
    cd $MODSECURITY_BUILD_PATH
    sudo git submodule init
    sudo git submodule update
    sudo ./build.sh
    sudo ./configure
    sudo make
    sudo make install
fi

# Compile and Install OpenResty with modules
cd $OPENRESTY_BUILD_PATH
sudo tar -xvf openresty-${OPENRESTY_VERSION}.tar.gz
cd openresty-${OPENRESTY_VERSION}/
sudo ./configure --prefix=$OPENRESTY_INSTALL_PATH -j2 --with-http_sub_module --with-http_stub_status_module --add-dynamic-module=$OPENRESTY_BUILD_PATH/modules/ngx_http_geoip2_module-3.3 --add-dynamic-module=$OPENRESTY_BUILD_PATH/modules/ngx_mod_security
sudo make -j2
sudo make install 

# Create additional folder structure
sudo mkdir $OPENRESTY_INSTALL_PATH/modsec
sudo mkdir $OPENRESTY_INSTALL_PATH/nginx/conf/certs
sudo mkdir $OPENRESTY_INSTALL_PATH/nginx/conf/server_blocks

# Set folder permissions
sudo setfacl -R -m u:$USER:rwx $OPENRESTY_INSTALL_PATH
sudo setfacl -R -m u:$USER:rwx $MODSECURITY_CRS
sudo setfacl -R -m u:$USER:rwx $GEOIP2_DB_PATH

# OWASP WAF Rules
export MODSECURITY_CONF=$OPENRESTY_INSTALL_PATH/modsec/modsecurity.conf
export MODSECURITY_CRS=/usr/local/modsecurity-crs
sudo rm -rf $MODSECURITY_CRS
sudo git clone https://github.com/coreruleset/coreruleset $MODSECURITY_CRS
sudo mv $MODSECURITY_CRS/crs-setup.conf.example $MODSECURITY_CRS/crs-setup.conf
sudo mv $MODSECURITY_CRS/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example $MODSECURITY_CRS/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf

# Create ModSecurity files
sudo cp $MODSECURITY_BUILD_PATH/unicode.mapping $OPENRESTY_INSTALL_PATH/modsec
sudo cp $MODSECURITY_BUILD_PATH/modsecurity.conf-recommended $MODSECURITY_CONF

export MODSEC_MAIN_FILE=$OPENRESTY_INSTALL_PATH/modsec/main.conf
if [ ! -f $MODSEC_MAIN_FILE ]; then
    sudo cat > $MODSEC_MAIN_FILE <<EOF
include ${OPENRESTY_INSTALL_PATH}/modsec/modsecurity.conf
include ${MODSECURITY_CRS}/crs-setup.conf
include ${MODSECURITY_CRS}/rules/*.conf

# test with http://somedomain.com/?testparam=thisisatestofmodsecurity
SecRule ARGS:testparam "@contains test" "id:1234,deny,log,status:403"
EOF
fi

# Create, enable and start OpenResty service 
export SERVICE_FILE=/etc/systemd/system/openresty.service
if [ ! -f $SERVICE_FILE ]; then   
    echo "# Stop dance for OpenResty
# =========================
#
# ExecStop sends SIGSTOP (graceful stop) to OpenResty's nginx process.
# If, after 5s (--retry QUIT/5) nginx is still running, systemd takes control
# and sends SIGTERM (fast shutdown) to the main process.
# After another 5s (TimeoutStopSec=5), and if nginx is alive, systemd sends
# SIGKILL to all the remaining processes in the process group (KillMode=mixed).
#
# nginx signals reference doc:
# http://nginx.org/en/docs/control.html
#
[Unit]
Description=The OpenResty Application Platform
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target
[Service]
Type=forking
PIDFile=$OPENRESTY_INSTALL_PATH/nginx/logs/nginx.pid
ExecStartPre=$OPENRESTY_INSTALL_PATH/nginx/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=$OPENRESTY_INSTALL_PATH/nginx/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=$OPENRESTY_INSTALL_PATH/nginx/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile $OPENRESTY_INSTALL_PATH/nginx/logs/nginx.pid
TimeoutStopSec=5
KillMode=mixed
[Install]
WantedBy=multi-user.target " | sudo tee -a $SERVICE_FILE >/dev/null
    sudo systemctl enable openresty
    sudo systemctl start openresty
    sudo systemctl status openresty
else
    sudo systemctl restart openresty
    sudo systemctl status openresty
fi

# Configure NGINX to enable ModSecurity and GeopIP2
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/g' $MODSECURITY_CONF
# Add module Imports
export NGINX_CONF=$OPENRESTY_INSTALL_PATH/nginx/conf/nginx.conf
export NGINX_CONF_HTTP_GEOIP_MODULE="load_module modules/ngx_http_geoip2_module.so;"
export NGINX_CONF_STREAM_GEOIP_MODULE="load_module modules/ngx_stream_geoip2_module.so;"
export NGINX_CONF_MOD_SECURITY_MODULE="load_module modules/ngx_http_modsecurity_module.so;"
if ! grep -q "$NGINX_CONF_HTTP_GEOIP_MODULE" "$NGINX_CONF" ; then
    sed -i "1 i ${NGINX_CONF_HTTP_GEOIP_MODULE}" $NGINX_CONF
fi
if ! grep -q "$NGINX_CONF_STREAM_GEOIP_MODULE" "$NGINX_CONF" ; then
    sed -i "1 i ${NGINX_CONF_STREAM_GEOIP_MODULE}" $NGINX_CONF
fi
if ! grep -q "$NGINX_CONF_MOD_SECURITY_MODULE" "$NGINX_CONF" ; then
    sed -i "1 i ${NGINX_CONF_MOD_SECURITY_MODULE}" $NGINX_CONF
fi
# Add server_blocks include to nginx.conf
if ! grep -q "server_blocks" "$NGINX_CONF" ; then
    sed -i "38 i \ \ \ \ include  '${OPENRESTY_INSTALL_PATH}/nginx/conf/server_blocks/*.conf';\n" $NGINX_CONF
fi
# Add GeoIP2 configuration
if ! grep -q "geoip2 /usr/local/etc/geoip2/GeoLite2-Country.mmdb" "$NGINX_CONF" ; then
    export GEOIP2_CONF='
    geoip2 /usr/local/etc/geoip2/GeoLite2-Country.mmdb {
        $geoip2_data_continent_code   continent code;
        $geoip2_data_country_iso_code country iso_code;
    }

    geoip2 /usr/local/etc/geoip2/GeoLite2-City.mmdb {
        $geoip2_data_city_name   city names en;
        $geoip2_data_postal_code postal code;
        $geoip2_data_latitude    location latitude;
        $geoip2_data_longitude   location longitude;
        $geoip2_data_state_name  subdivisions 0 names en;
        $geoip2_data_state_code  subdivisions 0 iso_code;
    }
    '
    export GEOIP2_CONF_PROCESSED=${GEOIP2_CONF//$'\n'/\\$'\n'}
    sed -i "40 i ${GEOIP2_CONF_PROCESSED}" $NGINX_CONF
fi

# Set path and secure path vars
export SECURE_PATHS_FILE=/etc/sudoers.d/secure_path_override
if [ ! -d $SECURE_PATHS_FILE ]; then
    echo "Defaults        secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$OPENRESTY_INSTALL_PATH/bin:$OPENRESTY_INSTALL_PATH/nginx/sbin\"" | sudo tee -a $SECURE_PATHS_FILE >/dev/null
fi

# Reload nginx config ('sudo openresty -s reload' also works)
sudo nginx -s reload

# Install ACME script
cd $OPENRESTY_BUILD_PATH
git clone https://github.com/acmesh-official/acme.sh.git
cd acme.sh
./acme.sh --install #-m you@yourdomain.com

# Clean up setup files
sudo rm -rf $OPENRESTY_BUILD_PATH

# DONE
echo "SCRIPT COMPLETE!"
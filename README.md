# OpenResty (NGINX) Automated Install Script

The idea behind this script is to automate the setup and configuration of an open-source NGINX/OpenResty server along with the popular ModSecurity WAF & GeoIP2 modules and their dependencies.

As an extra added bonus it will download and install acme.sh which you can use to create and auto-renew free SSL certificates. 

This script is basically an amalgamation of the following installation guides:
- OpenResrty https://openresty.org/en/installation.html
- ModSecurity WAF https://www.linode.com/docs/guides/securing-nginx-with-modsecurity/
- GeoIP2 https://github.com/leev/ngx_http_geoip2_module
- ACME https://github.com/acmesh-official/acme.sh#2-or-install-from-git

To run this script simply copy `install_openresty.sh` to your home directory and run it. You will require sudo right but you  

At the bottom of the script you will find the acme installation command where you may want to add your email address for notifications but it is not required.

> DISCLAIMER: This script is intended for fresh installs of Ubuntu or Dabian and currently has only been tested on Ubuntu 20.04 LTS. <BR> **DO NOT** run this script on a machine already running NGINX or OpenResty.

---  

## The script will perform the following actions in this order:

### 1) Downloads and Prerequisites:
 - Install prerequisites such as 'build-essential', 'make', 'perl' and others for OpenResty, GeoIP2, and/or ModSecurity specifically. 

 - Download MaxMinds GeoLite2 databases via [P3TERX](https://github.com/P3TERX/GeoLite.mmdb)

 - Download source code for GeopIP2 module.

 - Download source code for ModSecurity-NGINX connector module.

 - Download source code for ModSecurity.

### 2) Compiles and Installations:

 - Compile and install ModSecurity (unless already installed, because this takes ages).

 - Compile and install OpenResty with references to the source code for GeoIP2 and ModSecurity as dynamic modules. Also includes the `http_sub` and `http_stub_status` modules. You can add others if required.

### 3) Configurations

 - Creates additional folder structure for your ModSecurity configurations, your SSL certificates and your NGINX server config files.

 - Pulls the OWASP WAF Core Rule Set (CRS) from [coreruleset](https://github.com/coreruleset/).

 - Creates a `main.conf` in your ModSecurity config folder which references the CRS rules and includes an example custom WAF rule. Also copies a couple of other necessary CRS files to your ModSecurity folder.

 - Creates, enables and starts OpenResty service. (We do this before making additional  changes to make sure it's able to start with the default configuration) (If the service is already installed it just will be restarted).

 - Sets `SecRuleEngine` to `On` in ModSecurity's `main.conf` (default value is `DetectionOnly`).

 - Inserts `load_module` commands into `nginx.conf` for GeoIP2 and ModSecurity (`ngx_http_geoip2_module.so`, `ngx_stream_geoip2_module` and `ngx_http_modsecurity_module`) unless already present.

 - Inserts `include` command into `nginx.conf` for your server configuration files folder `server_blocks` unless already present.

 - Inserts to GeoIP2 database configuration blocks into `nginx.conf` unless already present.

 - Adds secure path for OpenResty (nginx) binary.

 - Runs `sudo nginx -s reload` to load the new configuration

### 4) Final Steps

 - Installs acme.sh.

 - Removes setup files.

---

Other notes:

- When creating a certificate with acme.sh, using the `--nginx` switch appears not to be supported with OpenResty. You can still use the command to create certificates without it:

- Check out the sample configuration and site in the example directory of this repo. It contains an nginx site configuration file which enables the ModSecurity WAF and uses GeopIP2 to populate a page with details of the clients location info. 

    To use the sample simply merge the `conf` folder in this repo with your own, pass in your own certificate files and reload nginx config.

    You can perform a simple test of the ModSecurity WAF by appending `?exec=/bin/bash` to the URL of site hosted or managed by your OpenResty server. If all is working the request will be blocked and OpenResty will return 403.

- There is also an `uninstall_openresty.sh` which will completely remove OpenResty, ModSecurity, acme.sh and all of the configuration files.
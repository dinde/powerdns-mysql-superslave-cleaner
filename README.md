powerdns-gmysql-cleaner
=======================

A bash script to clean PowerDNS's SuperSlave domains &amp; records
This script will clean all domains not anymore handled by a powerDNS SuperSlave server.
It works ONLY with mysql backend. It's based on default PDNS sql scheme.
You can crontab this file, there is a backup system embedded.

  ATTENTION: You need to use an external recursor.
  Don't execute this script with your /etc/resolv.conf
  With nameserver 127.0.0.1 (localhost). It just won't work.
  Also don't use one of the other dns declared for your domains.
  Set an external DNS to use this script (ie 8.8.8.8).

You can modify one function to get it working on any backend.
Feel free to request pull.

  This script has been sponsored by Open Web Network Solutions - http://www.owns.fr

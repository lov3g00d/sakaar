# CHANGEME - walkthrough (spoilers)

The intended path. Flags and the foothold secret are randomised per build, so
the only way in is the vuln itself - read the leaked secret, don't guess.

## 1. Recon
```
nmap -sV <ip>
```

## 2. Foothold (the vuln)
Describe the exploitation. The leaked secret is unique per build and not
guessable or crackable, so this vuln is the only foothold.

```
ssh CHANGEME@<ip>       # secret from the leaked output
cat ~/user.txt
```

## 3. Privilege escalation
```
sudo -l
# ... the intended privesc ...
cat /root/root.txt
```

The two flags match `vms/CHANGEME/flags.txt`, which the build engine writes for
the operator.

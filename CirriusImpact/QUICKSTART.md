Last login: Sun Oct 12 15:09:37 on ttys000
You have mail.
(base) terryr@MacBook-Pro-2 ~ % ssh kohademol
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-85-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Sun Oct 12 07:12:57 PM UTC 2025

  System load:  0.29               Processes:               360
  Usage of /:   13.3% of 97.87GB   Users logged in:         0
  Memory usage: 4%                 IPv4 address for ens160: 199.192.248.71
  Swap usage:   0%


Expanded Security Maintenance for Applications is not enabled.

0 updates can be applied immediately.

2 additional security updates can be applied with ESM Apps.
Learn more about enabling ESM Apps service at https://ubuntu.com/esm


Last login: Sun Oct 12 19:12:58 2025 from 73.45.151.55
library-koha@kohademo:~$ sudo koha-shell library
[sudo] password for library-koha: 
library-koha@kohademo:~$ vi plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact/QUICKSTART.md 
library-koha@kohademo:~$ vi plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact/QUICKSTART.md 






























```

**Phone Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. The following item was checked in: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Thank you!"
---
```

**Note:**
- WhatsApp is configured as an SMS notice using the `whatsapp:` section.
- CHECKIN notices automatically populate `itemsID`, `biblionumber`, `title`, and `date` fields by extracting the title from the rendered message and matching it to recent check-ins in the database (last 24 hours).

### Step 7: Test Message Processing

- Create a few Hold Reservations and Checkin the items to create a Hold Notification.

Run the message queue processor:

```bash
sudo koha-shell INSTANCE -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
```

Check the results:

```bash
ls -l /var/lib/koha/INSTANCE/CirriusImpact_archive/
tail -f /var/lib/koha/INSTANCE/CirriusImpact_archive/*.log
```

**Expected results:**
- ✅ No "regional phone numbers" error
- ✅ No "$self HASH" references in log
- ✅ CSV files created with message data
- ✅ Log files showing successful SFTP uploads
- ✅ All message fields populated (itemsID, title, phone, etc.)

**Check the output:**
```bash
# View CSV
cat ~/CirriusImpact_archive/*.csv | tail -10

# Check log
tail -50 ~/CirriusImpact_archive/*.log
```

## Verification

This was already done in Step 3 above, but lets re-run the verification to confirm:

```
✓ SMS::Send::US::CirriusImpact driver is installed (current)
✓ SMS::Send::CirriusImpact driver is installed (legacy)
✓ All required Perl modules found
"plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact/QUICKSTART.md" 360L, 11745B                                      216,0-1       62%

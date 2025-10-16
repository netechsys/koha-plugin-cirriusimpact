# CirriusImpact Plugin Installation Guide

## Overview

The CirriusImpact plugin integrates Koha's messaging system with CirriusImpact's SMS/voice/email notification service. Messages are exported as CSV files and uploaded via SFTP to CirriusImpact for processing.

**International Support:** The SMS::Send driver is an international-class driver that accepts phone numbers in any format (international or regional). It supports US, UK, Australian, and other international numbers.

## Prerequisites

- Koha 24.05 or higher
- Perl modules (usually already installed with Koha):
  - SMS::Send
  - SMS::Send::Driver
  - Net::SFTP::Foreign
  - YAML::XS
  - Template
  - Mojo::JSON

## Installation Steps

### 1. Install the Plugin

Upload the CirriusImpact.kpz file through the Koha plugin interface:

1. Go to: **Tools > Plugins > Upload Plugin**
2. Choose the `CirriusImpact.kpz` file
3. Click **Upload**

### 2. Install the SMS::Send Driver

The plugin requires a custom SMS::Send driver to integrate with Koha's message queue system.

**Option A: Automatic Installation (Recommended)**

Run the included installation script as root or with sudo:

```bash
sudo perl install_sms_driver.pl
```

**Option B: Manual Installation**

If you prefer to install manually:

```bash
# Copy the driver to the system Perl directory
sudo cp sms_driver/SMS/Send/CirriusImpact.pm /usr/share/perl5/SMS/Send/CirriusImpact.pm

# Set proper permissions
sudo chmod 644 /usr/share/perl5/SMS/Send/CirriusImpact.pm

# Verify installation
perl -MSMS::Send::CirriusImpact -e 'print "Driver installed successfully\n"'
```

### 3. Configure Koha System Preferences

Set the following system preferences in Koha:

**Administration > Global System Preferences > Patrons**

- **SMSSendDriver**: `US::CirriusImpact`
- **SMSSendUsername**: (leave blank - configured in plugin)
- **SMSSendPassword**: (leave blank - configured in plugin)

### 4. Configure the Plugin

1. Go to: **Tools > Plugins**
2. Find **CirriusImpact** in the list
3. Click **Actions > Configure**
4. Enter your configuration:
   - **SFTP Host**: Provided by CirriusImpact
   - **SFTP Username**: Provided by CirriusImpact
   - **SFTP Password**: Provided by CirriusImpact
   - **Archive Directory**: `/var/lib/koha/INSTANCE/CirriusImpact_archive`
   - **Enable SMS**: Check to enable SMS notifications
   - **Enable Phone**: Check to enable voice call notifications
   - **Enable Email**: Check to enable email notifications
   - **Enable WhatsApp**: Check to enable WhatsApp notifications
   - **Skip ODUE phone if SMS/Email**: Check to suppress voice calls when SMS/Email exists
5. Click **Save**

### 5. Configure Notice Templates

For each notice template you want to send through CirriusImpact, add the YAML header:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms_text: Your custom SMS message here
---
```

**Example HOLD notice:**

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "[% branch.branchname %] Hold ready: [% biblio.title %]. Questions? Call [% branch.branchphone %]"
  patronFirstName: [% borrower.firstname %]
  patronLastName: [% borrower.surname %]
  patronBarCode: [% borrower.cardnumber %]
  phone: [% borrower.smsalertnumber %]
  email: [% borrower.email %]
---
```

### 6. Set Up Message Queue Processing

The message queue should be processed regularly using the Koha cronjob:

Edit your Koha crontab (as the Koha instance user):

```bash
# Process message queue every 5 minutes
*/5 * * * * /usr/share/koha/bin/cronjobs/process_message_queue.pl
```

Or run manually:

```bash
sudo koha-shell INSTANCE -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
```

## Verification

### Test the SMS::Send Driver

Run the verification script:

```bash
sudo perl verify_installation.pl
```

Or manually:

```bash
perl -MSMS::Send::CirriusImpact -e 'print "Driver installed successfully\n"'
```

### Check Message Processing

1. Create a test patron with SMS notification preferences
2. Place a hold or create a checkout
3. Trigger a notice
4. Run the message queue processor:
   ```bash
   sudo koha-shell INSTANCE -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
   ```
5. Check the archive directory for CSV exports:
   ```bash
   ls -l /var/lib/koha/INSTANCE/CirriusImpact_archive/
   ```

### Check Logs

View the plugin logs:

```bash
tail -f /var/lib/koha/INSTANCE/CirriusImpact_archive/*.log
```

Look for:
- "Running CirriusImpact before_send_messages hook"
- "FOUND X MESSAGES TO PROCESS"
- "CI - FILE WRITTEN TO..."
- "CI - SFTP PUT..."

## Troubleshooting

### Error: "SMS::Send driver CirriusImpact does not exist"

**Solution:** The SMS::Send driver is not installed. Run:

```bash
sudo perl install_sms_driver.pl
```

### Error: "SFTP FAILED"

**Solution:** Check your SFTP credentials in the plugin configuration:
- Verify host, username, and password
- Ensure port 222 is accessible
- Check firewall rules

### No messages being processed

**Solution:** Verify your notice templates:
- Must include `CirriusImpact: yes` in YAML header
- Must be properly formatted YAML
- Check patron messaging preferences

### CSV files empty (header only)

**Cause:** No pending messages match the CirriusImpact criteria

**Check:**
1. Are notices configured with `CirriusImpact: yes`?
2. Are patrons set up with SMS preferences?
3. Run with verbose mode:
   ```bash
   CirriusImpact_VERBOSE=1 sudo koha-shell INSTANCE -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
   ```

## Environment Variables

Optional environment variables for testing:

- **CirriusImpact_TEST_MODE=1**: Don't delete/update messages (for testing)
- **CirriusImpact_VERBOSE=1**: Enable verbose logging
- **CirriusImpact_ARCHIVE_PATH**: Override archive directory path
- **CirriusImpact_SFTP_DIR**: Override SFTP remote directory

## File Locations

- **Plugin:** `/var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact.pm`
- **SMS Driver:** `/usr/share/perl5/SMS/Send/CirriusImpact.pm`
- **Archive:** `/var/lib/koha/INSTANCE/CirriusImpact_archive/`
- **Logs:** `/var/lib/koha/INSTANCE/CirriusImpact_archive/*.log`

## Uninstallation

To remove the plugin:

1. Uninstall through Koha: **Tools > Plugins > Actions > Uninstall**
2. Remove the SMS::Send driver:
   ```bash
   sudo rm /usr/share/perl5/SMS/Send/CirriusImpact.pm
   ```
3. Remove archive directory (optional):
   ```bash
   sudo rm -rf /var/lib/koha/INSTANCE/CirriusImpact_archive/
   ```

## Support

For issues or questions:

- **Plugin Issues:** Contact ByWater Solutions
- **CirriusImpact Service:** Contact CirriusImpact Support
- **Koha Issues:** Contact your Koha support provider

## Version History

- **1.1.6** (2025-10-11)
  - Added SMS::Send driver integration
  - Improved ODUE message handling
  - Enhanced CSV export format
  - Added multi-transport support

## License

Copyright 2025 CirriusImpact, LLC

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


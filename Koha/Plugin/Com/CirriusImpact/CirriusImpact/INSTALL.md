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

1. Download the latest `koha-plugin-cirriusimpact-v{VERSION}.kpz` file from the [GitHub releases page](https://github.com/netechsys/koha-plugin-cirriusimpact/releases)
2. In Koha, go to: **Tools > Plugins > Upload Plugin**
3. Upload the `.kpz` file
4. The plugin will automatically install, including the SMS::Send drivers

**Note:** The SMS::Send drivers (`SMS::Send::CirriusImpact` and `SMS::Send::US::CirriusImpact`) are automatically included in the KPZ and extracted during installation. They are discoverable via the plugin's @INC modification - **no manual installation required!**

### 2. Configure Koha System Preferences

Set the following system preferences in Koha:

**Administration > Global System Preferences > Patrons**

- **SMSSendDriver**: `US::CirriusImpact`
- **SMSSendUsername**: (leave blank - configured in plugin)
- **SMSSendPassword**: (leave blank - configured in plugin)

### 3. Configure the Plugin

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

### 4. Configure Notice Templates

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

### 5. Set Up Message Queue Processing

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

### Verify SMS::Send Driver Installation

The SMS drivers are automatically installed with the plugin. To verify they are discoverable:

```bash
perl -MSMS::Send::US::CirriusImpact -e 'print "US::CirriusImpact driver found\n"'
perl -MSMS::Send::CirriusImpact -e 'print "CirriusImpact driver found\n"'
```

Or run the verification script:

```bash
cd /var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/CirriusImpact/CirriusImpact/
perl verify_installation.pl
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

The plugin uses Koha::Logger for logging. Configure logging in your Koha log4perl configuration:

```perl
log4perl.logger.plugin.CirriusImpact = WARN, CIRRIUSIMPACT
log4perl.appender.CIRRIUSIMPACT=Log::Log4perl::Appender::File
log4perl.appender.CIRRIUSIMPACT.filename=/var/log/koha/INSTANCE/cirriusimpact.log
log4perl.appender.CIRRIUSIMPACT.mode=append
log4perl.appender.CIRRIUSIMPACT.layout=PatternLayout
log4perl.appender.CIRRIUSIMPACT.layout.ConversionPattern=[%d] [%p] %m%n
log4perl.appender.CIRRIUSIMPACT.utf8=1
```

Then view the logs:

```bash
tail -f /var/log/koha/INSTANCE/cirriusimpact.log
```

Look for:
- "Running CirriusImpact before_send_messages hook"
- "FOUND X MESSAGES TO PROCESS"
- "CI - FILE WRITTEN TO..."
- "CI - SFTP PUT..."

## Troubleshooting

### Error: "SMS::Send driver CirriusImpact does not exist"

**Solution:** This error is typically expected and can be safely ignored. The plugin uses the `before_send_messages` hook which runs before Koha's SMS::Send fallback mechanism. However, if you need to verify the drivers are accessible:

1. Ensure the plugin is installed and enabled
2. Check that the drivers are extracted at:
   - `/var/lib/koha/INSTANCE/plugins/SMS/Send/CirriusImpact.pm`
   - `/var/lib/koha/INSTANCE/plugins/SMS/Send/US/CirriusImpact.pm`
3. The plugin's BEGIN block automatically adds the plugins directory to @INC, so drivers should be discoverable
4. If drivers are missing, reinstall the plugin KPZ file

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

- **Plugin:** `/var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/CirriusImpact.pm`
- **SMS Driver (Source):** `/var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/CirriusImpact/CirriusImpact/sms_driver/SMS/Send/CirriusImpact.pm`
- **SMS Driver (US) (Source):** `/var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/CirriusImpact/CirriusImpact/sms_driver/SMS/Send/US/CirriusImpact.pm`
- **SMS Driver (Extracted):** `/var/lib/koha/INSTANCE/plugins/SMS/Send/CirriusImpact.pm` (automatically extracted during KPZ installation)
- **SMS Driver (US) (Extracted):** `/var/lib/koha/INSTANCE/plugins/SMS/Send/US/CirriusImpact.pm` (automatically extracted during KPZ installation)
- **Archive:** `/var/lib/koha/INSTANCE/CirriusImpact_archive/`
- **Logs:** Check Koha logs (configured via Koha::Logger, see log4perl configuration)

**Note:** The extracted SMS drivers in `SMS/Send/` are automatically created when you install the KPZ. The plugin's BEGIN block adds the plugins directory to Perl's @INC path, making these drivers discoverable without manual intervention.

## Uninstallation

To remove the plugin:

1. Uninstall through Koha: **Tools > Plugins > Actions > Uninstall**
2. The SMS::Send drivers in `SMS/Send/` will remain (they were extracted during installation). To completely remove them (optional):
   ```bash
   rm -f /var/lib/koha/INSTANCE/plugins/SMS/Send/CirriusImpact.pm
   rm -f /var/lib/koha/INSTANCE/plugins/SMS/Send/US/CirriusImpact.pm
   rmdir /var/lib/koha/INSTANCE/plugins/SMS/Send/US/ 2>/dev/null || true
   rmdir /var/lib/koha/INSTANCE/plugins/SMS/Send/ 2>/dev/null || true
   ```
3. Remove archive directory (optional):
   ```bash
   rm -rf /var/lib/koha/INSTANCE/CirriusImpact_archive/
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


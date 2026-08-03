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

1. Download the latest `koha-plugin-cirriusimpact-v{VERSION}.kpz` from the [GitLab releases page](https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases) (CirriusImpact may also provide the package directly)
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
2. Find **CirriusImpact** → **Actions > Configure**

#### Claim (preferred)

| Field | Purpose |
|-------|---------|
| **Bootstrap API URL** | Portal claim endpoint from CirriusImpact |
| **Library ID** | Portal library (standalone, Type 1, or Type 2 **root**) |
| **Install token** | One-time token from CirriusImpact |

Click **Claim / Re-claim**. Connection (Host / Username / Password / Archive dir) is filled from the Portal payload. You can still edit and **Save**.

Type 2 **members** must not Claim — only the root library on the shared Koha instance.

#### Branch services

There are no global Enable SMS / Phone checkboxes. Services are **per home branch** (opt-in; new branches default off).

**Standalone / Type 1 (`consortia_mode=shared`):** matrix columns **SMS**, **CIXL** (requires SMS), **Outbound** (voice).

**Type 2 (`consortia_mode=independent`):** **Member services** (SMS / CIXL / Outbound within Portal entitlements) plus **Branch → member** assignment.

On **Save**, the selection syncs to the Configuration Portal (requires a prior successful Claim).

Notices for an unchecked branch/service are **not exported**; those SMS/phone `message_queue` rows are marked **failed** with a reason.

#### Features

- **Skip calling ODUE if patron has SMS or Email**
- **Include messageText column in CSV output**

Click **Save**.

Manual Connection fields remain if CirriusImpact directs you not to use Claim. Typical archive path: `/var/lib/koha/INSTANCE/CirriusImpact_archive`.

### 4. Install Message Templates (Recommended)

**From Configure (preferred):** After saving Branch services, use **Install notice templates** on the plugin Configure page (mode, services, languages, confirm overwrite). No SSH required.

**From CLI** (same installer), as the Koha instance user **after** Configure/Save (so `--consortia-from-plugin` can read enabled branches):

```bash
sudo koha-shell INSTANCE -c \
  'perl /var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/CirriusImpact/CirriusImpact/install_message_templates.pl --no-restart'
```

#### Install modes (pick one)

| Mode | What it writes | When to use |
|------|----------------|-------------|
| `--defaults` (default) | Stock letter `CODE` at `branchcode=''` | Single-library sites |
| `--ci-templates` | `CODE-CI` only (`CHECKOUT-CI`, `HOLD-CI`, …); stock left alone | CI members use alternate letter codes |
| `--consortia-branch=CPL[,UPL…]` | Same `CODE`, branch-scoped `letter.branchcode` | Consortia; Koha prefers branch templates |
| `--consortia-from-plugin` | Same as `--consortia-branch` for every branch with a service enabled in Configure → **Branch services** | Consortia after the matrix is saved |

**Important:** `--consortia-branch=CPL` creates `CHECKOUT` with `branchcode=CPL`, **not** letter codes named `CHECKOUT-CPL` or `CHECKOUT-KDEMO_CPL`. Values are Koha branchcodes (`CPL`, `UPL`), not CirriusImpact library IDs (`KDEMO_CPL`).

The plugin export path recognizes both stock codes and `*-CI` variants.

#### What gets installed

- **19 notice codes** × **2 transports** (SMS + phone) when both services are selected
- **4 language rows** per template by default: `default`, `en`, `es-ES`, `fr-CA`
- Koha's **Default** tab (`letter.lang=default`) is filled from `--default-language` (English by default)
- SMS bodies use GSM-7-safe ASCII; see `TEMPLATE_I18N.md` for multilingual and character-budget notes

#### Command-line options

| Option | Description | Default |
|--------|-------------|---------|
| `--defaults` / `--ci-templates` / `--consortia-branch` / `--consortia-from-plugin` | Install mode (see above) | `--defaults` if none given |
| `--services=sms,phone` | Which transports to install (`sms` and/or `phone`) | both |
| `--default-language=…` | Language content for Koha's Default tab | `en` |
| `--languages=…` | Which `letter.lang` rows to write | `default,en,es-ES,fr-CA` |
| `--no-restart` | Skip the interactive Koha restart prompt | off |

`--transports` is accepted as an alias for `--services`.

**Service aliases:** `text` → `sms`; `voice` / `call` → `phone`

**Default-language aliases:** `en` / `eng`; `es-ES` / `spa`; `fr-CA` / `fre`

#### Install examples

**Single library** (stock defaults, SMS + phone, all languages):

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --defaults --no-restart'
```

**Consortia** (branch-scoped from Configure → Branch services):

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --consortia-from-plugin --no-restart'
```

**Consortia** (explicit branches):

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --consortia-branch=CPL,UPL --no-restart'
```

**CODE-CI only** (leave stock letters alone):

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --ci-templates --no-restart'
```

**SMS only** (library does not use voice):

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --services=sms --no-restart'
```

**Phone/voice only:**

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --services=phone --no-restart'
```

**Spanish-primary library** (Default tab = Spanish; English tab still populated):

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --default-language=spa --no-restart'
```

**SMS only, Spanish default, English + Spanish language rows only:**

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --services=sms --default-language=spa --languages=default,en,es-ES --no-restart'
```

#### Koha multilingual setup

For translated notice tabs to appear in the staff interface:

1. Set **TranslateNotices** = On
2. Add `en`, `es-ES`, and/or `fr-CA` to **OPACLanguages** (install language packs as needed)
3. Re-run the installer after changing languages or services

Patron `borrowers.lang` selects the notice row; missing translations fall back to `default`. The plugin maps Koha language tags to Notification Processor codes (`eng`, `spa`, `fre`) in the CSV `language` column.

### 5. Configure Notice Templates Manually (Alternative)

If you prefer not to use the installer, create or edit notices in **Tools > Notices**. For each template sent through CirriusImpact, add the YAML header:

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

See `QUICKSTART.md` for additional cut-and-paste examples by notice type.

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

**Solution:** Prefer **Claim / Re-claim** so Connection is filled from the Portal. Then verify:
- Host, username, and password on the Configure → Connection section
- Network path / firewall to the CirriusImpact SFTP endpoint (port provided by CirriusImpact)
- That you Claimed the correct Library ID (Type 2: root only)

### No messages being processed

**Solution:**
- Notice templates must include `CirriusImpact: yes` in the YAML header
- Patron messaging preferences must include SMS and/or phone as appropriate
- Configure → **Branch services**: the patron's home branch must have SMS and/or Outbound enabled
- Type 2: branch must be assigned to a member with that service entitled and enabled

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


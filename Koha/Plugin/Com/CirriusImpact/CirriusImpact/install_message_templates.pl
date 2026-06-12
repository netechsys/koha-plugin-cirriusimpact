#!/usr/bin/perl

use strict;
use warnings;
use DBI;

# CirriusImpact Message Template Installer
# This script installs default message templates for all supported message types

print "CirriusImpact Message Template Installer\n";
print "=======================================\n\n";

# Try to use Koha modules first, fall back to direct connection
my $dbh;
my $koha_available = 0;

eval {
    require C4::Context;
    require Koha::Database;
    $dbh = C4::Context->dbh;
    $koha_available = 1;
    print "✅ Connected to database via Koha modules\n";
};
if ($@) {
    print "⚠️  Koha modules not available, attempting direct connection...\n";
}

# If Koha modules not available, try direct connection
unless ($koha_available) {
    print "🔍 Attempting direct database connection...\n";
    
    # Try to read Koha config
    my $koha_conf = '/etc/koha/sites/library/koha-conf.xml';
    unless (-f $koha_conf) {
        print "❌ ERROR: Koha config file not found at $koha_conf\n";
        print "❌ Please run this script from within the Koha environment or ensure Koha is properly installed.\n";
        exit 1;
    }
    
    # Parse Koha config for database connection
    my ($host, $port, $database, $user, $password);
    open my $fh, '<', $koha_conf or die "Cannot open $koha_conf: $!";
    while (<$fh>) {
        if (/<host>(.*?)<\/host>/) { $host = $1; }
        elsif (/<port>(.*?)<\/port>/) { $port = $1; }
        elsif (/<database>(.*?)<\/database>/) { $database = $1; }
        elsif (/<user>(.*?)<\/user>/) { $user = $1; }
        elsif (/<pass>(.*?)<\/pass>/) { $password = $1; }
    }
    close $fh;
    
    unless ($host && $database && $user) {
        print "❌ ERROR: Could not parse database connection info from $koha_conf\n";
        exit 1;
    }
    
    $port ||= 3306;  # Default MySQL port
    
    eval {
        $dbh = DBI->connect("DBI:mysql:database=$database;host=$host;port=$port", $user, $password, {
            RaiseError => 1,
            AutoCommit => 1,
        });
        print "✅ Connected to database directly: $database on $host:$port\n";
    };
    if ($@) {
        print "❌ ERROR connecting to database: $@\n";
        exit 1;
    }
}

# Define all message templates
my %templates = (
    # HOLD Templates
    'HOLD_SMS' => {
        module => 'reserves',
        code => 'HOLD',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Hold ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---}
    },
    
    'HOLD_PHONE' => {
        module => 'reserves',
        code => 'HOLD',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] items ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]One item ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---}
    },
    
    # HOLDDGST Templates (Digest)
    'HOLDDGST_SMS' => {
        module => 'reserves',
        code => 'HOLDDGST',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF holds && holds.size > 1 %]You have [% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %][% ELSE %]Hold ready: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %][% END %]."
---}
    },
    
    'HOLDDGST_PHONE' => {
        module => 'reserves',
        code => 'HOLDDGST',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. You have [% IF holds && holds.size > 1 %][% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %][% ELSE %]a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %][% END %]. Call [% branch.branchphone %]."
---}
    },
    
    # CHECKOUT Templates
    'CHECKOUT_SMS' => {
        module => 'circulation',
        code => 'CHECKOUT',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF checkouts.size > 1 %]Checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %][% ELSE %]Checked out: [% biblio.title %]. Due [% checkout.date_due | $KohaDates %][% END %]"
---}
    },
    
    'CHECKOUT_PHONE' => {
        module => 'circulation',
        code => 'CHECKOUT',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF checkouts.size > 1 %]You checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %][% ELSE %]You checked out [% biblio.title %] due [% checkout.date_due | $KohaDates %][% END %]. Thank you!"
---}
    },
    
    # CHECKIN Templates
    'CHECKIN_SMS' => {
        module => 'circulation',
        code => 'CHECKIN',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF checkins.size > 1 %]Checked in [% checkins.size %] items: [% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Checked in: [% biblio.title %][% END %]. Thank you!"
---}
    },
    
    'CHECKIN_PHONE' => {
        module => 'circulation',
        code => 'CHECKIN',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. The following item was checked in: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Thank you!"
---}
    },
    
    # ODUE Templates (Simplified to avoid TT bugs)
    'ODUE_SMS' => {
        module => 'circulation',
        code => 'ODUE',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---}
    },
    
    'ODUE_PHONE' => {
        module => 'circulation',
        code => 'ODUE',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. You have an overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---}
    },
    
    # ODUE2 Templates
    'ODUE2_SMS' => {
        module => 'circulation',
        code => 'ODUE2',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Second notice - Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately. Call [% branch.branchphone %]."
---}
    },
    
    'ODUE2_PHONE' => {
        module => 'circulation',
        code => 'ODUE2',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. This is your second notice. You have an overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately. Call [% branch.branchphone %]."
---}
    },
    
    # ODUE3 Templates
    'ODUE3_SMS' => {
        module => 'circulation',
        code => 'ODUE3',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Final notice - Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately to avoid additional charges. Call [% branch.branchphone %]."
---}
    },
    
    'ODUE3_PHONE' => {
        module => 'circulation',
        code => 'ODUE3',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. This is your final notice. You have an overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately to avoid additional charges. Call [% branch.branchphone %]."
---}
    },
    
    # PREDUE Templates
    'PREDUE_SMS' => {
        module => 'circulation',
        code => 'PREDUE',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---}
    },
    
    'PREDUE_PHONE' => {
        module => 'circulation',
        code => 'PREDUE',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---}
    },
    
    # PREDUEDGST Templates
    'PREDUEDGST_SMS' => {
        module => 'circulation',
        code => 'PREDUEDGST',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---}
    },
    
    'PREDUEDGST_PHONE' => {
        module => 'circulation',
        code => 'PREDUEDGST',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---}
    },
    
    # Additional Message Types
    'HOLD_CHANGED_SMS' => {
        module => 'reserves',
        code => 'HOLD_CHANGED',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold status changed for [% biblio.title %]. Check your account for details. Call [% branch.branchphone %]."
---}
    },
    
    'HOLD_CHANGED_PHONE' => {
        module => 'reserves',
        code => 'HOLD_CHANGED',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your hold status has changed for [% biblio.title %]. Please check your account for details. Call [% branch.branchphone %]."
---}
    },
    
    'HOLD_REMINDER_SMS' => {
        module => 'reserves',
        code => 'HOLD_REMINDER',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - You have a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---}
    },
    
    'HOLD_REMINDER_PHONE' => {
        module => 'reserves',
        code => 'HOLD_REMINDER',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder - You have a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---}
    },
    
    # HOLDPLACED Templates
    'HOLDPLACED_SMS' => {
        module => 'reserves',
        code => 'HOLDPLACED',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold placed on [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
---}
    },
    
    'HOLDPLACED_PHONE' => {
        module => 'reserves',
        code => 'HOLDPLACED',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Hold placed on [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
---}
    },
    
    # HOLDPLACED_PATRON Templates
    'HOLDPLACED_PATRON_SMS' => {
        module => 'reserves',
        code => 'HOLDPLACED_PATRON',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold confirmed for [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
---}
    },
    
    'HOLDPLACED_PATRON_PHONE' => {
        module => 'reserves',
        code => 'HOLDPLACED_PATRON',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Hold confirmed for [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
---}
    },
    
    # HOLD_SLIP Template (in circulation module)
    'HOLD_SLIP_EMAIL' => {
        module => 'circulation',
        code => 'HOLD_SLIP',
        transport => 'email',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
email:
  subject: "Hold Slip - [% biblio.title %]"
  body: "Hold slip for [% biblio.title %]. Patron: [% borrower.firstname %] [% borrower.surname %]. Pickup by: [% hold.expirationdate | $KohaDates %]."
---}
    },
    
    'RENEWAL_SMS' => {
        module => 'circulation',
        code => 'RENEWAL',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] renewed. New due date: [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---}
    },
    
    'RENEWAL_PHONE' => {
        module => 'circulation',
        code => 'RENEWAL',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] has been renewed. New due date: [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---}
    },
    
    # AUTO_RENEWALS Templates
    'AUTO_RENEWALS_SMS' => {
        module => 'circulation',
        code => 'AUTO_RENEWALS',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] auto-renewed. New due date: [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---}
    },
    
    'AUTO_RENEWALS_PHONE' => {
        module => 'circulation',
        code => 'AUTO_RENEWALS',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] has been auto-renewed. New due date: [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---}
    },
    
    # AUTO_RENEWALS_DGST Templates
    'AUTO_RENEWALS_DGST_SMS' => {
        module => 'circulation',
        code => 'AUTO_RENEWALS_DGST',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF auto_renewals.size > 1 %][% auto_renewals.size %] items auto-renewed: [% FOREACH renewal IN auto_renewals %][% renewal.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Call [% branch.branchphone %]."
---}
    },
    
    'AUTO_RENEWALS_DGST_PHONE' => {
        module => 'circulation',
        code => 'AUTO_RENEWALS_DGST',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF auto_renewals.size > 1 %][% auto_renewals.size %] items have been auto-renewed: [% FOREACH renewal IN auto_renewals %][% renewal.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Call [% branch.branchphone %]."
---}
    },
    
    'MEMBERSHIP_EXPIRY_SMS' => {
        module => 'members',
        code => 'MEMBERSHIP_EXPIRY',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Your library membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew to continue using library services. Call [% branch.branchphone %]."
---}
    },
    
    'MEMBERSHIP_EXPIRY_PHONE' => {
        module => 'members',
        code => 'MEMBERSHIP_EXPIRY',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your library membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew to continue using library services. Call [% branch.branchphone %]."
---}
    },
    
    'MEMBERSHIP_RENEWED_SMS' => {
        module => 'members',
        code => 'MEMBERSHIP_RENEWED',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Your library membership has been renewed. New expiry date: [% borrower.dateexpiry | $KohaDates %]. Thank you!"
---}
    },
    
    'MEMBERSHIP_RENEWED_PHONE' => {
        module => 'members',
        code => 'MEMBERSHIP_RENEWED',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your library membership has been renewed. New expiry date: [% borrower.dateexpiry | $KohaDates %]. Thank you!"
---}
    },
    
    'WELCOME_SMS' => {
        module => 'members',
        code => 'WELCOME',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Welcome to the library, [% borrower.firstname %]! Your membership is active. Visit us soon!"
---}
    },
    
    'WELCOME_PHONE' => {
        module => 'members',
        code => 'WELCOME',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Welcome to the library! Your membership is now active. We look forward to serving you. Call [% branch.branchphone %]."
---}
    }
);

# Function to install a template
sub install_template {
    my ($name, $template) = @_;
    
    print "Installing $name... ";
    
    # Check if template already exists (ignore branchcode for detection)
    my $check_sth = $dbh->prepare("
        SELECT COUNT(*) FROM letter 
        WHERE module = ? AND code = ? AND message_transport_type = ?
    ");
    $check_sth->execute($template->{module}, $template->{code}, $template->{transport});
    my ($exists) = $check_sth->fetchrow_array;
    $check_sth->finish();
    
    
    # Generate proper title and name
    my $title = "$template->{code} - $template->{transport}";
    my $template_name = "$template->{code}";  # Same name for all transports of the same code
    
    if ($exists) {
        print "already exists, updating... ";
        # Update existing template - use consistent name for all transports of same code
        my $update_sth = $dbh->prepare("
            UPDATE letter 
            SET content = ?, name = ?, branchcode = '' 
            WHERE module = ? AND code = ? AND message_transport_type = ?
        ");
        $update_sth->execute($template->{content}, $template_name, $template->{module}, $template->{code}, $template->{transport});
        $update_sth->finish();
        print "updated.\n";
    } else {
        # Check if there are any existing templates with the same code but different name
        my $check_name_sth = $dbh->prepare("
            SELECT COUNT(*) FROM letter 
            WHERE module = ? AND code = ? AND message_transport_type = ? AND name != ?
        ");
        $check_name_sth->execute($template->{module}, $template->{code}, $template->{transport}, $template_name);
        my ($name_mismatch) = $check_name_sth->fetchrow_array;
        $check_name_sth->finish();
        
        if ($name_mismatch) {
            print "found existing with different name, updating... ";
            # Update existing template with different name
            my $update_sth = $dbh->prepare("
                UPDATE letter 
                SET content = ?, name = ?, branchcode = '' 
                WHERE module = ? AND code = ? AND message_transport_type = ?
            ");
            $update_sth->execute($template->{content}, $template_name, $template->{module}, $template->{code}, $template->{transport});
            $update_sth->finish();
            print "updated.\n";
        } else {
            # Insert new template
            my $insert_sth = $dbh->prepare("
                INSERT INTO letter (module, code, message_transport_type, content, title, name, branchcode)
                VALUES (?, ?, ?, ?, ?, ?, '')
            ");
            $insert_sth->execute($template->{module}, $template->{code}, $template->{transport}, $template->{content}, $title, $template_name);
            $insert_sth->finish();
            print "installed.\n";
        }
    }
}

# First, update all existing templates with inconsistent names
print "Checking for existing templates with inconsistent names...\n";
my $update_existing_sth = $dbh->prepare("
    UPDATE letter 
    SET name = code, branchcode = '' 
    WHERE name != code AND name IS NOT NULL AND code IS NOT NULL
");
my $updated_count = $update_existing_sth->execute();
$update_existing_sth->finish();
if ($updated_count > 0) {
    print "Updated $updated_count existing templates with inconsistent names.\n\n";
} else {
    print "All existing templates have consistent names.\n\n";
}

# Install all templates
print "Installing message templates...\n\n";

my $count = 0;
for my $name (sort keys %templates) {
    install_template($name, $templates{$name});
    $count++;
}

print "\n" . "=" x 50 . "\n";
print "Installation complete!\n";
print "Installed/Updated $count message templates.\n\n";

print "Next steps:\n";
print "1. Configure your CirriusImpact plugin settings\n";
print "2. Test the templates by creating test messages\n";
print "3. Customize templates as needed for your library\n\n";

print "Template categories installed:\n";
print "- HOLD (Hold ready notifications)\n";
print "- HOLDDGST (Hold digest notifications)\n";
print "- CHECKOUT (Item checkout notifications)\n";
print "- CHECKIN (Item return notifications)\n";
print "- ODUE/ODUE2/ODUE3 (Overdue notifications)\n";
print "- PREDUE/PREDUEDGST (Pre-due notifications)\n";
print "- HOLD_CHANGED (Hold status change notifications)\n";
print "- HOLD_REMINDER (Hold reminder notifications)\n";
print "- RENEWAL (Item renewal notifications)\n";
print "- AUTO_RENEWALS/AUTO_RENEWALS_DGST (Auto-renewal notifications)\n";
print "- MEMBERSHIP_EXPIRY (Membership expiry notifications)\n";
print "- MEMBERSHIP_RENEWED (Membership renewal notifications)\n";
print "- WELCOME (New member welcome notifications)\n\n";

print "All templates include CirriusImpact YAML markers and are ready to use!\n\n";

# Ask if user wants to restart Koha services
print "🔄 Koha Service Restart\n";
print "========================\n";
print "To ensure all changes take effect, you should restart Koha services.\n\n";

print "Would you like to restart Koha services now? (y/n): ";
my $restart_choice = <STDIN>;
chomp($restart_choice);

if ($restart_choice =~ /^[yY]/) {
    print "\n🔄 Restarting Koha services...\n";
    system("sudo systemctl restart koha-common");
    if ($? == 0) {
        print "✅ Koha services restarted successfully!\n";
    } else {
        print "❌ Failed to restart Koha services. You may need to restart manually.\n";
    }
} else {
    print "\n📋 Manual Restart Instructions:\n";
    print "===============================\n";
    print "To restart Koha services later, run:\n";
    print "  sudo systemctl restart koha-common\n\n";
    print "Or restart individual services:\n";
    print "  sudo systemctl restart apache2\n";
    print "  sudo systemctl restart koha-common\n\n";
    print "Alternatively, you can reboot the server:\n";
    print "  sudo reboot\n\n";
}

print "🎉 CirriusImpact plugin setup is now complete!\n";

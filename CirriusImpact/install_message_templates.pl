#!/usr/bin/perl

use strict;
use warnings;

# Enable output buffering
$| = 1;

print "🔍 Starting CirriusImpact Message Template Installer...\n";
print "🔍 Checking environment variables...\n";

# Check if we're running in Koha environment
unless ($ENV{KOHA_CONF}) {
    print "❌ ERROR: This script must be run within the Koha environment.\n";
    print "❌ KOHA_CONF environment variable not found.\n";
    print "❌ Please run it using: sudo koha-shell library -- perl install_message_templates.pl\n";
    print "❌ Or from the Koha plugins directory: sudo koha-shell library -- /var/lib/koha/library/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact/install_message_templates.pl\n";
    exit 1;
}

print "✅ KOHA_CONF found: $ENV{KOHA_CONF}\n";

# Try to load Koha modules with error handling
eval {
    require C4::Context;
    print "✅ C4::Context loaded successfully\n";
};
if ($@) {
    print "❌ ERROR loading C4::Context: $@\n";
    exit 1;
}

eval {
    require Koha::Database;
    print "✅ Koha::Database loaded successfully\n";
};
if ($@) {
    print "❌ ERROR loading Koha::Database: $@\n";
    exit 1;
}

# CirriusImpact Message Template Installer
# This script installs default message templates for all supported message types

print "🚀 CirriusImpact Message Template Installer\n";
print "==========================================\n\n";

print "📋 Connecting to Koha database... ";

# Connect to database with error handling
my $dbh;
eval {
    $dbh = C4::Context->dbh;
    print "✅ Connected to Koha database\n\n";
};
if ($@) {
    print "❌ ERROR connecting to database: $@\n";
    exit 1;
}

# Define all message templates
my %templates = (
    # HOLD Templates
    'HOLD_SMS' => {
        module => 'circulation',
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
        module => 'circulation',
        code => 'HOLD',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] items ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]One item ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Call 7315551234."
---}
    },
    
    # HOLDDGST Templates (Digest)
    'HOLDDGST_SMS' => {
        module => 'circulation',
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
        module => 'circulation',
        code => 'HOLDDGST',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. You have [% IF holds && holds.size > 1 %][% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %][% ELSE %]a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %][% END %]. Call 7315551234."
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
  text: "[% branch.branchcode %]: Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew. Call 7315551234."
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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. You have an overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew. Call 7315551234."
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
  text: "[% branch.branchcode %]: Second notice - Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately. Call 7315551234."
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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. This is your second notice. You have an overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately. Call 7315551234."
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
  text: "[% branch.branchcode %]: Final notice - Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately to avoid additional charges. Call 7315551234."
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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. This is your final notice. You have an overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately to avoid additional charges. Call 7315551234."
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
  text: "[% branch.branchcode %]: Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call 7315551234."
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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call 7315551234."
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
  text: "[% branch.branchcode %]: Reminder - [% IF upcoming_items.size > 1 %][% upcoming_items.size %] items due soon: [% FOREACH item IN upcoming_items %][% item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Please return or renew. Call 7315551234."
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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder - [% IF upcoming_items.size > 1 %][% upcoming_items.size %] items due soon: [% FOREACH item IN upcoming_items %][% item.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Please return or renew. Call 7315551234."
---}
    },
    
    # Additional Message Types
    'HOLD_CHANGED_SMS' => {
        module => 'circulation',
        code => 'HOLD_CHANGED',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold status changed for [% biblio.title %]. Check your account for details. Call 7315551234."
---}
    },
    
    'HOLD_CHANGED_PHONE' => {
        module => 'circulation',
        code => 'HOLD_CHANGED',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your hold status has changed for [% biblio.title %]. Please check your account for details. Call 7315551234."
---}
    },
    
    'HOLD_REMINDER_SMS' => {
        module => 'circulation',
        code => 'HOLD_REMINDER',
        transport => 'sms',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - You have a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %]. Call 7315551234."
---}
    },
    
    'HOLD_REMINDER_PHONE' => {
        module => 'circulation',
        code => 'HOLD_REMINDER',
        transport => 'phone',
        content => q{---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder - You have a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %]. Call 7315551234."
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
  text: "[% branch.branchcode %]: [% biblio.title %] renewed. New due date: [% issue.date_due | $KohaDates %]. Call 7315551234."
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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] has been renewed. New due date: [% issue.date_due | $KohaDates %]. Call 7315551234."
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
  text: "[% branch.branchcode %]: Your library membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew to continue using library services. Call 7315551234."
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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your library membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew to continue using library services. Call 7315551234."
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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Welcome to the library! Your membership is now active. We look forward to serving you. Call 7315551234."
---}
    }
);

# Function to install a template
sub install_template {
    my ($name, $template) = @_;
    
    print "📝 Installing $name... ";
    
    eval {
        # Check if template already exists
        my $check_sth = $dbh->prepare("
            SELECT COUNT(*) FROM letter 
            WHERE module = ? AND code = ? AND message_transport_type = ?
        ");
        $check_sth->execute($template->{module}, $template->{code}, $template->{transport});
        my ($exists) = $check_sth->fetchrow_array;
        $check_sth->finish();
        
        if ($exists) {
            print "🔄 already exists, updating... ";
            # Update existing template
            my $update_sth = $dbh->prepare("
                UPDATE letter 
                SET content = ? 
                WHERE module = ? AND code = ? AND message_transport_type = ?
            ");
            $update_sth->execute($template->{content}, $template->{module}, $template->{code}, $template->{transport});
            $update_sth->finish();
            print "✅ updated.\n";
        } else {
            # Insert new template
            my $insert_sth = $dbh->prepare("
                INSERT INTO letter (module, code, message_transport_type, content, title)
                VALUES (?, ?, ?, ?, ?)
            ");
            my $title = "$template->{code} - $template->{transport}";
            $insert_sth->execute($template->{module}, $template->{code}, $template->{transport}, $template->{content}, $title);
            $insert_sth->finish();
            print "✅ installed.\n";
        }
    };
    if ($@) {
        print "❌ ERROR: $@\n";
        return 0;
    }
    return 1;
}

# Install all templates
print "📦 Installing message templates...\n";
print "📊 Total templates to process: " . scalar(keys %templates) . "\n\n";

my $count = 0;
my $success_count = 0;
my $total = scalar(keys %templates);

for my $name (sort keys %templates) {
    $count++;
    print "[$count/$total] ";
    if (install_template($name, $templates{$name})) {
        $success_count++;
    }
}

print "\n" . "🎉" . "=" x 48 . "🎉\n";
print "✅ Installation complete!\n";
print "📈 Successfully processed $success_count out of $count message templates.\n";
if ($success_count < $count) {
    print "⚠️  Some templates failed to install. Check error messages above.\n";
}
print "\n";

print "📋 Next steps:\n";
print "   1️⃣  Configure your CirriusImpact plugin settings\n";
print "   2️⃣  Test the templates by creating test messages\n";
print "   3️⃣  Customize templates as needed for your library\n\n";

print "📚 Template categories installed:\n";
print "   📌 HOLD (Hold ready notifications)\n";
print "   📌 HOLDDGST (Hold digest notifications)\n";
print "   📌 CHECKOUT (Item checkout notifications)\n";
print "   📌 CHECKIN (Item return notifications)\n";
print "   📌 ODUE/ODUE2/ODUE3 (Overdue notifications)\n";
print "   📌 PREDUE/PREDUEDGST (Pre-due notifications)\n";
print "   📌 HOLD_CHANGED (Hold status change notifications)\n";
print "   📌 HOLD_REMINDER (Hold reminder notifications)\n";
print "   📌 RENEWAL (Item renewal notifications)\n";
print "   📌 MEMBERSHIP_EXPIRY (Membership expiry notifications)\n";
print "   📌 MEMBERSHIP_RENEWED (Membership renewal notifications)\n";
print "   📌 WELCOME (New member welcome notifications)\n\n";

print "🎯 All templates include CirriusImpact YAML markers and are ready to use!\n";
print "🚀 CirriusImpact plugin setup is now complete!\n";

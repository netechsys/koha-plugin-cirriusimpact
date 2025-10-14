#!/usr/bin/perl

use strict;
use warnings;

# Enable output buffering
$| = 1;

print "🔍 CirriusImpact Template Verification Script\n";
print "==========================================\n\n";

# Try to load required modules
eval {
    require DBI;
    print "✅ DBI module loaded successfully\n";
};
if ($@) {
    print "❌ ERROR loading DBI: $@\n";
    exit 1;
}

# Try to load Koha modules with error handling
my $koha_available = 0;
eval {
    require C4::Context;
    print "✅ C4::Context loaded successfully\n";
    $koha_available = 1;
};
if ($@) {
    print "⚠️  C4::Context not available, will use direct database connection\n";
}

# Get database connection
my $dbh;
if ($koha_available) {
    eval {
        $dbh = C4::Context->dbh;
        print "✅ Connected to Koha database via C4::Context\n";
    };
    if ($@) {
        print "❌ ERROR connecting via C4::Context: $@\n";
        $koha_available = 0;
    }
}

# If Koha modules not available, try direct connection
unless ($koha_available) {
    print "🔍 Attempting direct database connection...\n";
    
    # Try to read Koha config
    my $koha_conf = '/etc/koha/sites/library/koha-conf.xml';
    unless (-f $koha_conf) {
        print "❌ ERROR: Koha config file not found at $koha_conf\n";
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

print "\n📋 Checking for CirriusImpact templates...\n\n";

# Check for ODUE2 and ODUE3 templates specifically
my @codes_to_check = qw(ODUE2 ODUE3);
my @transports = qw(sms phone);

foreach my $code (@codes_to_check) {
    print "🔍 Checking $code templates:\n";
    
    foreach my $transport (@transports) {
        my $sth = $dbh->prepare("
            SELECT module, code, message_transport_type, title, 
                   CASE WHEN content LIKE '%CirriusImpact%' THEN 'YES' ELSE 'NO' END as has_cirrius
            FROM letter 
            WHERE code = ? AND message_transport_type = ?
        ");
        $sth->execute($code, $transport);
        my $row = $sth->fetchrow_hashref;
        $sth->finish();
        
        if ($row) {
            print "   ✅ $transport: Found - Module: $row->{module}, Title: $row->{title}, CirriusImpact: $row->{has_cirrius}\n";
        } else {
            print "   ❌ $transport: NOT FOUND\n";
        }
    }
    print "\n";
}

# Check all CirriusImpact templates
print "📊 Summary of all CirriusImpact templates:\n";
my $sth = $dbh->prepare("
    SELECT code, message_transport_type, 
           CASE WHEN content LIKE '%CirriusImpact%' THEN 'YES' ELSE 'NO' END as has_cirrius
    FROM letter 
    WHERE content LIKE '%CirriusImpact%'
    ORDER BY code, message_transport_type
");
$sth->execute();

my $count = 0;
while (my $row = $sth->fetchrow_hashref) {
    $count++;
    print "   [$count] $row->{code} - $row->{message_transport_type} (CirriusImpact: $row->{has_cirrius})\n";
}
$sth->finish();

print "\n📈 Total CirriusImpact templates found: $count\n";

# Check for any templates with ODUE codes
print "\n🔍 All ODUE-related templates:\n";
$sth = $dbh->prepare("
    SELECT code, message_transport_type, title
    FROM letter 
    WHERE code LIKE 'ODUE%'
    ORDER BY code, message_transport_type
");
$sth->execute();

while (my $row = $sth->fetchrow_hashref) {
    print "   📌 $row->{code} - $row->{message_transport_type}: $row->{title}\n";
}
$sth->finish();

print "\n✅ Verification complete!\n";

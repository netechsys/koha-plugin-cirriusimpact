# Notification Type and Level Lookup Table

This document describes the notification type and level mapping for all supported CirriusImpact message types.

## Overview

The `_get_notification_type_and_level()` function provides a lookup table that maps Koha message codes to:
- **Notification Type**: Categorizes the type of notification (1-6)
- **Notification Level**: Indicates the severity/priority level within that type (1-6)

## Usage

```perl
my $result = _get_notification_type_and_level('ODUE2');
my $type = $result->{type};   # Returns 1
my $level = $result->{level}; # Returns 2
```

## Notification Types

### Type 1: Overdue Notices
| Message Code | Level | Description |
|--------------|-------|-------------|
| ODUE         | 1     | First overdue notice |
| ODUE2        | 2     | Second overdue notice |
| ODUE3        | 3     | Third overdue notice |
| DUE          | 4     | Overdue notice (some sites use `DUE` instead of `ODUE` in overduerules) |
| DUEDGST      | 4     | Overdue digest (if configured) |

### Type 2: Hold Notices
| Message Code | Level | Description |
|--------------|-------|-------------|
| HOLD              | 1     | Item ready for pickup |
| HOLDDGST          | 1     | Item ready for pickup (digest) |
| HOLD_CHANGED      | 2     | Hold status changed |
| HOLD_REMINDER     | 3     | Hold reminder |
| HOLDPLACED        | 4     | Hold placed confirmation |
| HOLDPLACED_PATRON | 5     | Hold placed confirmation (patron) |
| HOLD_SLIP         | 6     | Hold slip (email) |

### Type 3: Circulation Notices
| Message Code | Level | Description |
|--------------|-------|-------------|
| CHECKOUT | 1 | Item checked out |
| CHECKIN  | 2 | Item checked in |

### Type 4: Pre-due Notices
| Message Code | Level | Description |
|--------------|-------|-------------|
| PREDUE     | 1 | Pre-due reminder |
| PREDUEDGST | 1 | Pre-due reminder (digest) |

### Type 5: Renewal Notices
| Message Code | Level | Description |
|--------------|-------|-------------|
| RENEWAL            | 1 | Manual renewal confirmation |
| AUTO_RENEWALS      | 2 | Auto-renewal notification |
| AUTO_RENEWALS_DGST | 2 | Auto-renewal notification (digest) |

### Type 6: Membership Notices
| Message Code | Level | Description |
|--------------|-------|-------------|
| MEMBERSHIP_EXPIRY  | 1 | Membership expiring |
| MEMBERSHIP_RENEWED | 2 | Membership renewed |
| WELCOME            | 3 | Welcome message |

## Implementation

The lookup table is implemented in `CirriusImpact.pm` as the `_get_notification_type_and_level()` function:

```perl
sub _get_notification_type_and_level {
    my ($letter_code) = @_;
    
    my %notification_mapping = (
        # Overdue Notices - Type 1
        'ODUE'  => { type => 1, level => 1 },
        'ODUE2' => { type => 1, level => 2 },
        'ODUE3' => { type => 1, level => 3 },
        
        # Hold Notices - Type 2
        'HOLD'              => { type => 2, level => 1 },
        'HOLDDGST'          => { type => 2, level => 1 },
        'HOLD_CHANGED'      => { type => 2, level => 2 },
        'HOLD_REMINDER'     => { type => 2, level => 3 },
        'HOLDPLACED'        => { type => 2, level => 4 },
        'HOLDPLACED_PATRON' => { type => 2, level => 5 },
        'HOLD_SLIP'         => { type => 2, level => 6 },
        
        # Circulation Notices - Type 3
        'CHECKOUT' => { type => 3, level => 1 },
        'CHECKIN'  => { type => 3, level => 2 },
        
        # Pre-due Notices - Type 4
        'PREDUE'      => { type => 4, level => 1 },
        'PREDUEDGST'  => { type => 4, level => 1 },
        
        # Renewal Notices - Type 5
        'RENEWAL'           => { type => 5, level => 1 },
        'AUTO_RENEWALS'     => { type => 5, level => 2 },
        'AUTO_RENEWALS_DGST' => { type => 5, level => 2 },
        
        # Membership Notices - Type 6
        'MEMBERSHIP_EXPIRY'  => { type => 6, level => 1 },
        'MEMBERSHIP_RENEWED' => { type => 6, level => 2 },
        'WELCOME'            => { type => 6, level => 3 },
    );
    
    return $notification_mapping{$letter_code} || { type => 0, level => 0 };
}
```

## Error Handling

- Returns `{ type => 0, level => 0 }` for unknown/unsupported message codes
- This allows calling code to handle unsupported types gracefully

## Testing

Run the test script to verify the lookup table:

```bash
perl test_notification_lookup.pl
```

This will display all supported message codes with their corresponding type and level values.

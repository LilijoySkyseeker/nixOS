# Alert on octodns-sync deletes

## Goal

Hear about a DNS record deletion when it happens. On 2026-09-12 a
*successful* `octodns-sync` run (exit 0, `Deletes=3`) wiped the
Workspace mail records; `health-alerts` only fires on failed units, so
it was silent. With MX and DKIM in the zone, the same run now breaks
inbound mail and DMARC within the 300s TTL.

## Your decisions

None yet.

## State

Not started.

## Next

Alert when `octodns-sync` reports any delete: a delete is never routine
for a declarative zone.

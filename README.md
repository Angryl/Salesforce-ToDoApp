# Journey Planner

A Salesforce unlocked package for people who spend their day visiting customers: plan visits, check in and out with GPS, and get time spent and distance travelled automatically.

## What it does

1. **Plan** the day on a timeline. Each visit is a standard Salesforce Event linked to an Account, Contact, Opportunity, Lead, or any custom object you enable. Click an empty slot to create one. Overlaps get a warning, never a block.
2. **Check in and out** of each visit from your phone. Location is captured when you tap the button, and you can add a meeting summary.
3. **See the numbers**: time spent per visit, distance from the previous visit, and day totals (visits, minutes, km).

<!-- screenshot: planner -->
<!-- screenshot: visit card -->
<!-- gif: check-in flow -->

## Install

**Status: not yet released. The install link is coming with v1.0.**

Once released, the steps are:

1. Open the install link: _TBD_.
2. Assign the **Journey Planner User** permission set to your users (or **Journey Planner Admin** for admins).
3. Open the **Journey Planner** app.

The Event record page (visit card with Check in / Check out) is activated inside the Journey Planner app, on desktop and phone, through app overrides. To use it outside the app, activate **Journey Event Record Page** for Event in Lightning App Builder.

## Configure

### Supported objects

Rows of the `Journey_Object__mdt` custom metadata type decide which objects can be linked to a visit. Shipped: Account and Opportunity (via `WhatId`), Contact and Lead (via `WhoId`).

To add a custom object:

1. Enable **Allow Activities** on the object.
2. Add a `Journey_Object__mdt` row with its API name, relation field (`WhatId` or `WhoId`), display field, icon and effective dates.

### Settings and versioning

`Journey_Setting__mdt` holds the global settings. Shipped defaults:

| Setting                       | Default |
| ----------------------------- | ------- |
| Road factor                   | 1.30    |
| Default visit length          | 60 min  |
| Location accuracy warning     | 200 m   |
| Summary required at check-out | No      |

Settings are versioned by date. `Effective From` and `Effective To` are both inclusive, and a blank `Effective To` means open-ended.

To change a setting:

1. Add a **new** `Journey_Setting__mdt` record with the new values and an `Effective From` date.
2. Set the previous version's `Effective To` to the day before.

Past journeys keep the road factor and summary rule they started with, so history never changes. The **Journey Planner Admin** tab lists gaps and overlaps between versions. If two active versions overlap on a date, the planner stops with a clear admin-facing error instead of guessing.

## How distance works

- Distance is the straight-line distance between two check-in/out points **multiplied by the road factor**. Kilometres only.
- A leg runs from the previous check-out (or **Start day**, for the first visit) to the next check-in. The first visit with no Start day has a leg of 0.
- **End day** adds one more leg from the last check-out.
- Day total km is the sum of all legs.

Straight-line is an estimate. A road-distance provider can be plugged in later through the `DistanceCalculator` interface.

## Privacy

- Location is captured **only when the user taps** Check in, Check out, Start day or End day.
- Nothing is tracked in the background.
- If location is unavailable (permission denied, no fix, timeout), the action is **blocked**. No visit is stamped without coordinates.
- Data is stored on Event and Journey records **in your own org**. Nothing leaves it.

## Permissions and security

- Two permission sets: **Journey Planner User** and **Journey Planner Admin**, plus matching custom permissions.
- Users cannot edit or delete check-in/out data. Admins can, and admin edits recalculate the day totals.
- Apex runs in user mode and respects sharing.

## Known limitations

- The planner places times in the **browser's time zone**. Keep the device and Salesforce user time zones the same.
- Deleting a record that has completed visits is blocked for non-admins.
- An admin deleting a completed visit does not yet recalculate day totals.
- Admins need access to the Event (sharing) to correct another user's visit.
- The timeline shows 07:00-21:00.

## Architecture

- `Journey__c`: one record per user per day, holding totals and the settings snapshot.
- Custom fields on Event for check-in/out, location, time spent, leg distance and status.
- `Journey_Setting__mdt` and `Journey_Object__mdt`: versioned configuration.
- `JourneyService`: check-in/out, journey get-or-create, bulk-safe recalculation. `JourneyController` exposes it to LWC.
- `DistanceCalculator` interface with a straight-line implementation.
- Event trigger guard: blocks manual edits of check-in/out data.
- LWCs: `journeyPlanner`, `journeyTimeline`, `journeyVisitCard`, `journeyEventForm`, `journeyConfigCheck`, and the `locationUtil` helper.

**Standard-object-first:** visits are plain Events, so nothing needs migrating and the standard calendar, reports and sharing keep working. Only what Events cannot hold (a per-day total) gets a custom object.

## Development

Prerequisites: Node 22, the Salesforce CLI (`sf`), and a Dev Hub org.

```
npm install
npm run lint
npm run test:unit
npm run scan
```

Scratch org:

```
sf org create scratch --definition-file config/project-scratch-def.json --alias jp-scratch --set-default --duration-days 7
sf project deploy start --target-org jp-scratch
sf org assign permset --name Journey_Planner_Admin --target-org jp-scratch
sf apex run test --target-org jp-scratch --code-coverage --result-format human --wait 20
```

CI (GitHub Actions) always runs the static job: lint, Prettier, Jest and Code Analyzer. The scratch-org job (deploy plus Apex tests) runs only when the repo secret `DEVHUB_SFDX_AUTH_URL` is set.

## Roadmap

- Tasks and to-dos on the timeline
- Calendar sync (Outlook, Google)
- Road-distance provider (Google or Salesforce Maps)
- Manager dashboards
- Agentforce "plan my day"

## License

MIT. See [LICENSE](LICENSE).

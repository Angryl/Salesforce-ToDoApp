# Journey Planner — Design

Status: Ready for approval · Date: 2026-11-23 · Owner: Rudra Pratap Singh

## 1. Intent

A generic, installable Salesforce module for people who spend their day visiting customers. Each morning a user plans the day as a timeline of visits (standard Events) linked to Accounts, Contacts, Opportunities, Leads, or any admin-enabled custom object. During the day they check in and check out of each visit from their phone, and record a meeting summary. The module works out time spent per visit, distance between visits, and the day's total time on visits and km driven.

It exists to be **shown to clients and prospects and installed by them**. It must demonstrate good architecture (standard-object-first, secure, tested, configurable) and work as a real tool after a one-link install. It contains nothing specific to any client.

## 2. Goals, non-goals, anti-goals

**Goals (v1)**
- Day-view planner: see one day's visits on a timeline; click an empty slot to create an Event pre-filled with that start/end; pick the related record.
- Overlap warning when Events on the same day overlap in time (warn, never block).
- Per Event: Meeting Summary, Check-in and Check-out buttons capturing time and location, time spent, distance from the previous visit.
- Per day (Journey): total time on visits, total km driven.
- Generic: supported objects configured, not coded.
- Versioned, effective-dated configuration: a new setting applies from its start date without changing results already calculated under an older one.
- Installable as an unlocked package; works in the Salesforce mobile app.

**Non-goals (v1)**
- Tasks (no to-do list, no time-blocking of Tasks).
- Calendar sync with Outlook/Google, and handling of externally synced meetings.
- Road distance from Google Maps or Salesforce Maps (v1 is straight-line × road factor; design leaves room for a provider later).
- Multi-day views, route optimisation, maps, manager/team dashboards, approvals, expense claims.
- Continuous location tracking.

**Anti-goals (would make it a failure even if it works)**
- Location captured at any time other than the user tapping a button.
- Recalculating past Journeys with new settings (silently changing historical km).
- Anything that forces a client to migrate data or replace standard Events.
- Client-specific names, data or logic in the repo.

## 3. Constraints and platform facts

- Event custom fields live on the Activity object and are shared with Task; they are hidden from Task layouts.
- Nothing can hold a lookup to an Event, and Events cannot be the parent of roll-up summaries. Journey totals are calculated in Apex.
- Store latitude/longitude as Number(10,7) fields (Geolocation-type support on Activity is not clearly documented). Apex `Location.newInstance()` + `Location.getDistance()` works on plain numbers.
- Device location comes from LWC `LocationService` (`lightning/mobileCapabilities`) inside the Salesforce mobile app. On desktop the component falls back to the browser Geolocation API and records the source, since browser accuracy is poor.
- Location capture needs user consent (OS prompt). Capture is only on button tap — this is the module's stated privacy position (relevant to India's DPDP Act and clients' HR/legal review).
- Dates are the user's local date (user's time zone), not UTC.
- Must pass Salesforce Code Analyzer (PMD) and be bulk-safe; all Apex `with sharing` and enforcing CRUD/FLS.

## 4. Approaches considered

| | Approach | Trade-off | Decision |
|---|---|---|---|
| 1 | Standard Event + custom Journey object, custom LWC planner, Apex service layer, Custom Metadata config, unlocked package | Most code; strongest demo; standard-object-first | **Chosen** by Rudra |
| 2 | Mostly declarative: Screen Flows + standard calendar | Less code, but no overlap warnings or slot-click create; GPS still needs a custom component | Rejected |
| 3 | Custom Visit object as master record, Event created alongside | Proper roll-ups and field types, but two records per visit kept in sync; contradicts "use standard Event" | Rejected |

## 5. Decisions made with Rudra

- Visits are standard **Events** (StartDateTime, EndDateTime, ActivityDate, WhatId, WhoId already exist).
- Supported related objects: Account, Contact, Opportunity, Lead, plus custom objects an admin enables (the object must have "Allow Activities" on).
- Scheduling from the timeline by clicking an empty slot. Overlap = warning only.
- Meeting Summary on each Event. Check-in and check-out capture time + location.
- Distance between visits and journey km use **straight-line distance × admin road factor** (option A).
- Location captured **only on button tap**.
- Configuration is **versioned by effective date** (§8).
- Only Salesforce-created Events are in scope; sync is out.

## 6. Data model

### 6.1 Event (Activity) — new custom fields

| Field | Type | Purpose |
|---|---|---|
| Journey__c | Lookup(Journey__c) | Day this visit belongs to |
| Meeting_Summary__c | Long Text Area (32k) | Post-visit notes. If Activity rejects Long Text Area in a scratch org, use standard Event Description instead (builder verifies first) |
| Check_In_Time__c / Check_Out_Time__c | Date/Time | Stamped on button tap |
| Check_In_Latitude__c / Check_In_Longitude__c | Number(10,7) | Check-in location |
| Check_Out_Latitude__c / Check_Out_Longitude__c | Number(10,7) | Check-out location |
| Check_In_Accuracy_m__c / Check_Out_Accuracy_m__c | Number | Reported GPS accuracy in metres |
| Location_Source__c | Picklist: Mobile GPS, Browser | Where location came from |
| Time_Spent_Minutes__c | Number | Check-out minus check-in |
| Distance_From_Previous_Km__c | Number(8,2) | Leg distance into this visit (after road factor) |
| Visit_Status__c | Picklist: Planned, Checked In, Completed | Drives buttons and validation |

### 6.2 Journey__c (new custom object, one per user per day)

| Field | Type | Purpose |
|---|---|---|
| OwnerId | standard | The user |
| Journey_Date__c | Date | User-local date |
| Unique_Key__c | Text, External ID, Unique | `<UserId>_<yyyy-MM-dd>`, prevents duplicates |
| Start_Latitude__c / Start_Longitude__c / Start_Time__c | Number / Date/Time | Optional "Start day" location (§7.4) |
| End_Latitude__c / End_Longitude__c / End_Time__c | Number / Date/Time | Optional "End day" location |
| Total_Visit_Minutes__c | Number | Sum of Time_Spent over completed visits |
| Total_Km__c | Number(10,2) | Sum of legs, after road factor |
| Visit_Count__c | Number | Completed visits |
| Applied_Setting__c | Text | DeveloperName of the config version stamped on this journey |
| Applied_Road_Factor__c | Number(4,2) | Road factor snapshot |
| Applied_Require_Summary__c | Checkbox | Snapshot of the summary rule |

Name: auto-number `JRN-{000000}`. OWD Private; access via ownership and role hierarchy.

### 6.3 Custom Metadata (configuration)

**Journey_Setting__mdt** — versioned global settings
- Effective_From__c (Date, required), Effective_To__c (Date, blank = open-ended)
- Road_Factor__c (Number, default 1.30), Require_Summary_On_Checkout__c (Checkbox, default false), Default_Visit_Minutes__c (default 60), Max_Location_Accuracy_m__c (warn above this, default 200), Is_Active__c

**Journey_Object__mdt** — versioned list of supported objects
- Object_API_Name__c, Relation_Field__c (WhatId / WhoId), Display_Field__c (e.g. Name), Icon_Name__c (SLDS icon), Effective_From__c, Effective_To__c, Is_Active__c, Sort_Order__c

Shipped records: Account, Opportunity (WhatId); Contact, Lead (WhoId); one Journey_Setting v1 effective from 2000-01-01, open-ended.

## 7. Behaviour

### 7.1 Planner (day view)
- LWC `journeyPlanner` on a Lightning app page and mobile nav. Date picker, previous/next day; default today.
- Shows the user's Events whose ActivityDate (or span) falls on that day, ordered by StartDateTime, with related record, status, time spent, leg distance.
- Clicking an empty slot opens a create form pre-filled with start = slot, end = start + Default_Visit_Minutes; user picks object type (from Journey_Object__mdt valid for that date) and record (`lightning-record-picker`), subject.
- Drag/resize to reschedule is allowed only while Visit_Status = Planned.
- Day summary header: visits planned/completed, total time, total km (from Journey__c).

### 7.2 Overlap warning
- On create or reschedule, check the user's other Events that day: overlap when `newStart < otherEnd && newEnd > otherStart`. All-day events are ignored.
- Show a warning naming the conflicting event(s) with "Keep both" / "Change time". Overlapping cards show a warning marker on the timeline. Never blocks save.

### 7.3 Check-in / check-out
- LWC `journeyVisitCard` on the Event record page (and opened from the planner).
- **Check in** (status Planned → Checked In): get location; stamp time, lat/long, accuracy, source; attach the Event to the user's Journey for today (get-or-create by Unique_Key__c).
- **Check out** (Checked In → Completed): get location; stamp; compute Time_Spent_Minutes; compute Distance_From_Previous_Km (§7.4); recalculate the Journey totals.
- If accuracy is worse than Max_Location_Accuracy_m__c, warn but allow.
- **No location, no check-in/out (hard block).** If permission is denied, the device can't get a fix, or the call times out, the button does nothing except show how to enable location and a Retry option. No visit is ever stamped without coordinates, so every leg has real points.
- If Require_Summary_On_Checkout__c is true for the journey's stamped version, check-out requires a Meeting Summary.
- Only one visit may be Checked In at a time per user; checking in to another prompts to check out the first.

### 7.4 Distance and totals
- A leg's origin is the previous point in the journey: the most recent check-out earlier that day, or the Journey start location if "Start day" was captured and this is the first visit. First visit with no start location → leg = 0.
- Leg km = `Location.getDistance(origin, checkIn, 'km') × Applied_Road_Factor__c`.
- Journey.Total_Km = sum of legs + (End day location ? distance last check-out → end × factor : 0).
- Journey.Total_Visit_Minutes = sum of Time_Spent over completed visits. Visit_Count likewise.
- Totals are recalculated by `JourneyService.recalculate(journeyIds)` (bulk-safe) after check-out, start/end day, and when a completed visit is edited by an admin.

### 7.5 Versioned configuration
- Resolver picks the record where `Is_Active && Effective_From <= journeyDate && (Effective_To = null || Effective_To >= journeyDate)`.
- On first creation of a Journey, the resolved version's DeveloperName and Road_Factor are **stamped** onto it. All later calculations for that Journey use the stamp, never re-resolve. Result: a new version applies to new days only; past journeys never change.
- Object list resolves by the planner's selected date, so an object added from 1 Jan appears only for dates from 1 Jan.
- If two active versions overlap for a date, the resolver fails closed with a clear admin-facing error. An admin "Configuration check" panel lists gaps and overlaps.

## 8. Security

- Permission sets: **Journey Planner User** (Journey__c read/create/edit own; FLS on new Event fields; app and tab access) and **Journey Planner Admin** (adds View All on Journey__c, config panel).
- Apex: `with sharing`, `WITH USER_MODE` queries / `Security.stripInaccessible` on DML; no SOQL in loops; bulk-safe triggers via a handler.
- Check-in/out fields are written only through the Apex service; an Event trigger guard (bypassed by the service, allowed for holders of the Journey_Planner_Admin custom permission) blocks manual edits of check-in/out fields except by admins, and blocks deleting an Event once checked in.

## 9. Components (indicative)

- LWC: `journeyPlanner`, `journeyTimeline`, `journeyVisitCard`, `journeyEventForm`, `journeyConfigCheck`; shared `locationUtil` (LocationService with browser fallback).
- Apex: `JourneyController` (Aura-enabled entry points), `JourneyService` (get-or-create journey, check-in/out, recalc), `DistanceCalculator` (interface + `StraightLineDistanceCalculator`, so a road-distance provider can be added later), `JourneyConfig` (versioned resolver), `EventTriggerHandler`.
- Metadata: Journey__c, Event fields, two CMDTs with shipped records, permission sets, Lightning app + app page, Event record page component placement, validation rules.

## 10. Quality, packaging, repo

- Repo: SFDX project in `Angryl/Salesforce-ToDoApp` (public, MIT). Rename of the repo is optional (§11).
- Tests: Apex unit tests ≥ 90% coverage with meaningful asserts (overlap edges, distance maths, config version selection and stamping, bulk 200 records, permission tests with `System.runAs`). LWC Jest tests for planner and visit card.
- CI (GitHub Actions): on PR — Prettier/ESLint, Jest, Salesforce Code Analyzer; scratch-org deploy + Apex tests once a Dev Hub auth secret is provided.
- Packaging: unlocked package; install link in README.
- README: what it does, screenshots/GIF, install, configuration (including versioning), privacy statement, architecture notes, roadmap.
- Commits and PRs authored by Rudra only; no AI attribution lines.

## 11. Open questions and calls

**Calls made by Claude (Rudra to check):**
- Distance unit is km only in v1 (no Miles option), so stored values never change meaning.
- Meeting Summary is optional by default; a versioned setting can make it required at check-out.
- Product working name: "Journey Planner".

**Decided by Rudra:**
- Location unavailable → hard block (§7.3).
- Unlocked package **with a namespace**. Rudra's own free Developer Edition org is enabled as the **Dev Hub**; the namespace is registered in a **second, separate** Developer Edition org and linked to the Dev Hub. Neither org may belong to an employer or client. The namespace string is chosen by Rudra at registration (must be globally unique; cannot be changed later). The builder writes code namespace-agnostic and sets `namespace` in `sfdx-project.json` once registered.
- Known limit: a Developer Edition Dev Hub is not a production org; if it is deactivated through inactivity, installed versions can't be upgraded. Log in to both orgs regularly.

## 12. Left to the builder
- Exact LWC layout and styling within SLDS; timeline granularity (15 vs 30 min).
- Naming prefix to avoid collisions in client orgs.
- Trigger framework style.

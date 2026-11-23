# Journey Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an installable Salesforce unlocked package that lets a user plan a day of visits (standard Events), check in/out with GPS, and see time spent and km driven per visit and per day.

**Architecture:** Standard Event + custom `Journey__c` (one per user per day). Thin `@AuraEnabled` controller → `JourneyService` (check-in/out, recalc) using `JourneyConfig` (effective-dated Custom Metadata resolver) and a `DistanceCalculator` interface. LWCs for the day planner, visit card and config check. Event trigger guards check-in data.

**Tech Stack:** Salesforce DX (sf CLI 2.x), Apex, LWC, Custom Metadata, Jest (`@salesforce/sfdx-lwc-jest`), Salesforce Code Analyzer, GitHub Actions, unlocked package with namespace.

**Spec:** `docs/superpowers/specs/2026-11-23-journey-planner-design.md` — read it first; this plan does not repeat its rationale.

## Global Constraints

- All Apex `with sharing`; SOQL `WITH USER_MODE`; DML via `Database.*(…, AccessLevel.USER_MODE)` except service-owned check-in fields (system writes inside `JourneyService`, guarded by the trigger bypass).
- No SOQL/DML in loops; every service method takes collections; tests include a 200-record bulk case.
- Apex coverage ≥ 90% per class, every test has meaningful `Assert.*` calls.
- Code is namespace-agnostic: no hard-coded namespace prefixes; `sfdx-project.json` `"namespace": ""` until Rudra registers it (Task 11).
- `sourceApiVersion` = the Dev Hub's current max API version (from `sf org display --target-org devhub --json` → `apiVersion`), never below 60.0.
- Distance unit km only. Road factor default 1.30. Default visit length 60 min. Max location accuracy warning 200 m. Require summary default false.
- Location is captured only inside a user-tapped check-in/out/start/end action. No location ⇒ action fails (hard block); nothing is stamped.
- Journey date = the user's local date (`Datetime.format('yyyy-MM-dd', UserInfo.getTimeZone().getID())`), never UTC date.
- Unique_Key__c format: `<18-char UserId>_<yyyy-MM-dd>`.
- No client names anywhere. Commits authored by Rudra Pratap Singh `<Angryl@users.noreply.github.com>`, no AI attribution lines.

**Org-dependent verification:** steps marked `[org]` need a scratch org from Rudra's Dev Hub (alias `devhub`). Until Rudra authorises it, run every `[local]` step, mark `[org]` steps as pending in the task notes, and continue; they are executed in a single catch-up pass once the Dev Hub is available.

## Review Focus

1. **Midnight / time zone:** an IST user checking in at 00:30 local must land on that local date's Journey, not the previous UTC date — test in Task 4.
2. **Double tap / retry:** a second check-in call on an already Checked In visit, or two calls creating the same day's Journey, must not create duplicates — tests in Task 4.
3. **Admin edits a completed visit's times or coordinates:** totals must recalculate — test in Task 5.
4. **Config boundary dates:** a journey dated exactly Effective_From or exactly Effective_To resolves to that version (both inclusive); a gap returns a clear error — tests in Task 2.
5. **User without the permission set** opening the planner gets a readable message, not a stack trace — test in Task 6.

---

### Task 0: SFDX project scaffold and CI

**Files:**
- Create: `sfdx-project.json`, `config/project-scratch-def.json`, `.forceignore`, `.gitignore`, `package.json`, `jest.config.js`, `.prettierrc`, `eslint.config.js` (LWC recommended config), `.github/workflows/ci.yml`, `README.md` (replace)

**Interfaces:**
- Produces: npm scripts `lint`, `test:unit`, `prettier:verify`, `scan`; package directory `force-app` (default, package name `Journey Planner`).

- [ ] **Step 1:** Write `sfdx-project.json` with one package directory `force-app`, `"package": "Journey Planner"`, `"versionName": "v1.0"`, `"versionNumber": "1.0.0.NEXT"`, `"namespace": ""`, `sourceApiVersion` per Global Constraints. Scratch def: edition Developer, features `["EnableSetPasswordInApi"]`, settings `lightningExperienceSettings.enableS1DesktopEnabled: true`.
- [ ] **Step 2:** `package.json` devDependencies: `@salesforce/sfdx-lwc-jest@^7`, `@salesforce/eslint-config-lwc`, `eslint`, `prettier`, `prettier-plugin-apex`, `@prettier/plugin-xml`. Scripts: `"test:unit": "sfdx-lwc-jest --passWithNoTests"`, `"lint": "eslint force-app/**/lwc/**/*.js"`, `"prettier:verify": "prettier --check \"force-app/**/*.{cls,trigger,js,html,xml,json}\""`, `"scan": "sf code-analyzer run --target force-app --view table --severity-threshold 2"`.
- [ ] **Step 3:** Run `npm install && npm run test:unit && npm run lint && npm run prettier:verify`. Expected: all exit 0.
- [ ] **Step 4:** `ci.yml` on `pull_request` and `push` to `main`: job `static` (node 22: `npm ci`, lint, prettier:verify, test:unit; install `@salesforce/cli`, `sf plugins install code-analyzer`, `npm run scan`). Job `org` runs only `if: ${{ secrets.DEVHUB_SFDX_AUTH_URL != '' }}` (use an env var check): auth Dev Hub from secret, create scratch org (`--duration-days 1`), deploy, `sf apex run test --code-coverage --result-format human --wait 20`, delete scratch org in `always()`.
- [ ] **Step 5:** README skeleton with sections: What it does, Install, Configure (incl. versioned settings), Privacy (button-tap location only), Architecture, Development, Roadmap.
- [ ] **Step 6:** Commit `chore: scaffold SFDX project, tooling and CI`.

---

### Task 1: Data model, configuration metadata, permissions

**Files (under `force-app/main/default/`):**
- Create: `objects/Journey__c/` (object + fields per spec §6.2; Name auto-number `JRN-{000000}`; sharing model Private)
- Create: `objects/Activity/fields/*.field-meta.xml` for every spec §6.1 field (Journey__c lookup with relationship name `Visits`, delete constraint SetNull)
- Create: `objects/Journey_Setting__mdt/` and `objects/Journey_Object__mdt/` with fields per spec §6.3 (minus Distance_Unit; plus Require_Summary_On_Checkout__c)
- Create: `customMetadata/Journey_Setting.V1.md-meta.xml` (Effective_From 2000-01-01, To blank, Road_Factor 1.30, Default_Visit_Minutes 60, Max_Location_Accuracy_m 200, Require_Summary false, Is_Active true)
- Create: `customMetadata/Journey_Object.Account|Opportunity|Contact|Lead.md-meta.xml` (Account/Opportunity → WhatId, Contact/Lead → WhoId; Display_Field Name; icons `standard:account`, `standard:opportunity`, `standard:contact`, `standard:lead`; Effective_From 2000-01-01; Sort_Order 10/20/30/40)
- Create: `customPermissions/Journey_Planner_Admin.customPermission-meta.xml`
- Create: `permissionsets/Journey_Planner_User.permissionset-meta.xml`, `Journey_Planner_Admin.permissionset-meta.xml` (Admin adds View All on Journey__c + the custom permission)

**Interfaces:**
- Produces: all API names exactly as spec §6 (e.g. `Event.Check_In_Latitude__c`, `Journey__c.Unique_Key__c`, `Journey__c.Applied_Road_Factor__c`, `Journey__c.Applied_Require_Summary__c`); `Visit_Status__c` values `Planned` (default), `Checked In`, `Completed`; `Location_Source__c` values `Mobile GPS`, `Browser`.

- [ ] **Step 1 [local]:** Write the metadata. Run `sf project convert source --root-dir force-app --output-dir /tmp/mdapi-check`. Expected: exit 0.
- [ ] **Step 2 [org]:** Create scratch org, `sf project deploy start`. Expected: success. If `Meeting_Summary__c` Long Text Area is rejected on Activity, delete that field, use standard `Description` everywhere `Meeting_Summary__c` appears in later tasks, and note it in the task report.
- [ ] **Step 3:** Commit `feat: data model, versioned config metadata and permission sets`.

---

### Task 2: JourneyConfig — effective-dated resolver

**Files:**
- Create: `classes/JourneyConfig.cls`, `classes/JourneyConfigException.cls`, `classes/JourneyConfigTest.cls`

**Interfaces:**
- Produces:
  - `static Journey_Setting__mdt settingFor(Date d)` — the single active record with `From <= d && (To == null || To >= d)`; throws `JourneyConfigException` with message containing the date if none or more than one match.
  - `static List<Journey_Object__mdt> objectsFor(Date d)` — active, valid on `d`, sorted by `Sort_Order__c`; duplicates of the same Object_API_Name valid on the same date → exception.
  - `static List<String> healthIssues(Date fromDate, Date toDate)` — human-readable gaps/overlaps for settings across the range (checked day by day only at version boundaries, not every day).
  - `@TestVisible static List<Journey_Setting__mdt> settingsOverride; @TestVisible static List<Journey_Object__mdt> objectsOverride;` — tests inject records built in memory.

- [ ] **Step 1: Write failing tests** in `JourneyConfigTest`:
  - `settingFor_picksVersionOnBoundaries`: V1 2026-01-01→2026-06-30, V2 2026-07-01→null; assert `settingFor(2026-06-30).DeveloperName == 'V1'`, `settingFor(2026-07-01).DeveloperName == 'V2'`, `settingFor(2026-01-01).DeveloperName == 'V1'`.
  - `settingFor_gapThrows`: V1 to 2026-06-30, V2 from 2026-07-05; `settingFor(2026-07-02)` throws, message contains `2026-07-02`.
  - `settingFor_overlapThrows`: both valid on 2026-07-01 → throws.
  - `settingFor_ignoresInactive`.
  - `objectsFor_respectsDatesAndOrder`: Custom object row from 2026-08-01 absent on 2026-07-31, present on 2026-08-01, sorted by Sort_Order.
  - `healthIssues_reportsGapAndOverlap`: returns 2 entries for a range containing one gap and one overlap.
- [ ] **Step 2 [org]:** `sf apex run test --class-names JourneyConfigTest --wait 10` → FAIL (class missing).
- [ ] **Step 3:** Implement. Real path queries `Journey_Setting__mdt.getAll().values()` / `Journey_Object__mdt.getAll().values()` (no SOQL), filtered in Apex.
- [ ] **Step 4 [org]:** rerun → PASS, coverage ≥ 90%.
- [ ] **Step 5:** Commit `feat: effective-dated configuration resolver`.

---

### Task 3: DistanceCalculator

**Files:**
- Create: `classes/DistanceCalculator.cls` (interface), `classes/StraightLineDistanceCalculator.cls`, `classes/GeoPoint.cls`, `classes/DistanceCalculatorTest.cls`

**Interfaces:**
- Produces:
  - `public class GeoPoint { public Decimal latitude; public Decimal longitude; public GeoPoint(Decimal lat, Decimal lng) }`
  - `public interface DistanceCalculator { Decimal kmBetween(GeoPoint a, GeoPoint b); }` — raw distance, no road factor, rounded to 3 dp.
  - `StraightLineDistanceCalculator implements DistanceCalculator` using `Location.newInstance(...).getDistance(..., 'km')`.

- [ ] **Step 1: Failing tests:** `(0,0)→(0,1)` ≈ 111.195 km (assert within 0.01); same point → 0; null point → `IllegalArgumentException`.
- [ ] **Step 2 [org]:** run → FAIL. **Step 3:** implement. **Step 4 [org]:** run → PASS.
- [ ] **Step 5:** Commit `feat: straight-line distance calculator`.

---

### Task 4: JourneyService — journeys, check-in/out, totals

**Files:**
- Create: `classes/JourneyService.cls`, `classes/JourneyException.cls`, `classes/LocationReading.cls`, `classes/JourneyServiceTest.cls`, `classes/JourneyTestData.cls` (`@IsTest` factory)

**Interfaces:**
- Consumes: `JourneyConfig.settingFor`, `DistanceCalculator`, `GeoPoint`.
- Produces:
  - `public class LocationReading { @AuraEnabled public Decimal latitude; @AuraEnabled public Decimal longitude; @AuraEnabled public Decimal accuracyMeters; @AuraEnabled public String source; }` (`source` ∈ `Mobile GPS`, `Browser`)
  - `static Journey__c getOrCreateJourney(Id userId, Date journeyDate)` — upsert on `Unique_Key__c`; on create stamps `Applied_Setting__c`, `Applied_Road_Factor__c`, `Applied_Require_Summary__c` from `settingFor(journeyDate)`; never re-stamps an existing Journey.
  - `static Date localDate(Datetime dt)` — user-local date.
  - `static CheckResult checkIn(Id eventId, LocationReading loc)` / `static CheckResult checkOut(Id eventId, LocationReading loc, String summary)`
  - `public class CheckResult { @AuraEnabled public Id eventId; @AuraEnabled public Id journeyId; @AuraEnabled public Boolean lowAccuracy; @AuraEnabled public Decimal legKm; @AuraEnabled public Integer minutesSpent; }`
  - `static Journey__c startDay(Date d, LocationReading loc)` / `static Journey__c endDay(Date d, LocationReading loc)`
  - `static void recalculate(Set<Id> journeyIds)` — bulk; sets each completed visit's `Distance_From_Previous_Km__c` and the Journey totals per spec §7.4 using the Journey's stamped road factor.
  - `@TestVisible static DistanceCalculator calculator = new StraightLineDistanceCalculator();`
  - `@TestVisible static Boolean bypassGuard` — set true while the service writes check-in fields (read by Task 5 trigger).

**Rules (spec §7.3–7.4):** location null or lat/long null → `JourneyException('Location is required to check in. Enable location and retry.')`; event not owned by current user → exception; checkIn when status ≠ Planned → exception; another Event of this user already `Checked In` → exception naming it; checkOut when status ≠ Checked In → exception; stamped `Applied_Require_Summary__c` true and summary blank → exception; accuracy > setting's Max_Location_Accuracy → `lowAccuracy = true` (not an error). Leg origin = previous completed visit's check-out point (ordered by `Check_Out_Time__c`) else Journey start point if set else none (leg 0). Leg km = raw × stamped factor, rounded 2 dp. Journey totals: sum legs + end-day leg; minutes = sum `Time_Spent_Minutes__c`; `Visit_Count__c` = completed count.

- [ ] **Step 1: Failing tests** (use a mock `DistanceCalculator` returning 10.000 km per call so totals are exact):
  - `checkIn_stampsAndAttachesJourney` (status Checked In, coords stamped, Journey created with Applied_Road_Factor 1.30).
  - `checkIn_withoutLocation_throwsAndStampsNothing`.
  - `checkIn_twice_throws`; `checkIn_whileAnotherCheckedIn_throws`.
  - `getOrCreateJourney_isIdempotent` (two calls → one record).
  - `checkOut_computesMinutesAndLeg`: three visits, no start day → legs 0, 13.00, 13.00; Journey Total_Km 26.00, Visit_Count 3.
  - `startAndEndDay_countFirstAndLastLegs`: start + 2 visits + end → Total_Km 39.00.
  - `requireSummary_enforcedFromStampedVersion`: journey stamped true → checkOut with blank summary throws; a later version change to false does not alter it.
  - `newConfigVersion_doesNotChangePastJourney`: recalc yesterday's journey after override switches factor to 1.50 → Total_Km unchanged.
  - `localDate_usesUserTimeZone`: runAs user with `Asia/Kolkata`; `localDate(Datetime.newInstanceGmt(2026,11,23,19,0,0))` == 2026-11-24.
  - `recalculate_bulk200`: 200 completed visits across 4 journeys, one call, within limits.
  - `lowAccuracy_flaggedNotBlocked`.
- [ ] **Step 2 [org]:** run → FAIL. **Step 3:** implement. **Step 4 [org]:** run → PASS, coverage ≥ 90%.
- [ ] **Step 5:** Commit `feat: journey service for check-in, check-out and totals`.

---

### Task 5: Event trigger guard

**Files:**
- Create: `triggers/EventTrigger.trigger` (before update, before delete, after update), `classes/EventTriggerHandler.cls`, `classes/EventTriggerHandlerTest.cls`

**Interfaces:**
- Consumes: `JourneyService.bypassGuard`, `JourneyService.recalculate`, custom permission `Journey_Planner_Admin`.

**Rules:** unless `bypassGuard` or `FeatureManagement.checkPermission('Journey_Planner_Admin')`: (a) changes to any `Check_In_*`/`Check_Out_*`/`Visit_Status__c`/`Time_Spent_Minutes__c`/`Distance_From_Previous_Km__c` → `addError`; (b) changes to `StartDateTime`/`EndDateTime` when status ≠ Planned → `addError`; (c) delete when status ≠ Planned → `addError`. After update by an admin touching guarded fields on a Completed visit → recompute that visit's `Time_Spent_Minutes__c` and call `recalculate` for its Journey.

- [ ] **Step 1: Failing tests:** user cannot edit check-in lat; user cannot reschedule checked-in visit; user cannot delete checked-in visit; user can reschedule Planned visit; admin edit of check-out time recalculates Journey minutes; bulk update 200 Planned events passes.
- [ ] **Step 2–4 [org]:** fail → implement → pass.
- [ ] **Step 5:** Commit `feat: protect check-in data on Event`.

---

### Task 6: JourneyController (Apex API for LWCs)

**Files:**
- Create: `classes/JourneyController.cls`, `classes/OverlapChecker.cls`, `classes/JourneyControllerTest.cls`

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces (all `@AuraEnabled`; errors surfaced as `AuraHandledException` with readable messages):
  - `getDay(Date dayDate) → DayView` (cacheable=false). `DayView { Journey__c journey; List<VisitRow> visits; List<ObjectOption> objectOptions; Integer defaultVisitMinutes; }`; `VisitRow { Id id; String subject; Datetime startTime; Datetime endTime; Boolean allDay; String status; Id relatedId; String relatedName; String relatedObject; String iconName; Integer minutesSpent; Decimal legKm; String summary; List<Id> overlapsWith; }`; `ObjectOption { String apiName; String relationField; String label; String iconName; String displayField; }`
  - `createVisit(String subject, Datetime startTime, Datetime endTime, Id relatedId) → CreateResult { Id eventId; List<VisitRow> overlaps; }` — sets WhatId or WhoId from the related record's sObject type via `objectsFor(localDate(startTime))`; rejects types not configured.
  - `rescheduleVisit(Id eventId, Datetime startTime, Datetime endTime) → CreateResult`
  - `checkIn(Id eventId, LocationReading loc)`, `checkOut(Id eventId, LocationReading loc, String summary)` → `JourneyService.CheckResult`; `startDay(Date d, LocationReading loc)`, `endDay(...)` → `Journey__c`
  - `getConfigHealth() → List<String>` (Admin custom permission required; range today−365 → today+365)
  - `OverlapChecker.overlaps(List<Event> sameDay, Datetime s, Datetime e, Id excludeId) → List<Event>`: `s < other.End && e > other.Start`, ignores all-day events and `excludeId`.

- [ ] **Step 1: Failing tests:** overlap edge cases (touching 10:00–11:00 vs 11:00–12:00 → no overlap; contained; all-day ignored); `getDay` returns visits sorted by start with overlap ids; `createVisit` on Lead sets WhoId, on Account sets WhatId, on an unconfigured object throws readable message; `getDay` runAs user **without** permission set → `AuraHandledException` whose message mentions "Journey Planner User"; `getConfigHealth` without admin permission throws.
- [ ] **Step 2–4 [org]:** fail → implement → pass.
- [ ] **Step 5:** Commit `feat: controller API for planner and visit card`.

---

### Task 7: LWC `locationUtil`

**Files:**
- Create: `lwc/locationUtil/locationUtil.js`, `.js-meta.xml` (not exposed), `lwc/locationUtil/__tests__/locationUtil.test.js`

**Interfaces:**
- Produces: `export function getCurrentLocation({ timeoutMs = 15000 } = {}) → Promise<{ latitude, longitude, accuracyMeters, source }>`; rejects with `Error` whose `code` ∈ `'DENIED' | 'UNAVAILABLE' | 'TIMEOUT'`.

- [ ] **Step 1: Failing Jest tests:** uses `getLocationService()` when `isAvailable()` is true → source `Mobile GPS` (mock `lightning/mobileCapabilities`); falls back to `navigator.geolocation` → source `Browser`; permission denied → rejects `DENIED`; neither available → `UNAVAILABLE`; times out → `TIMEOUT`.
- [ ] **Step 2:** `npm run test:unit -- locationUtil` → FAIL. **Step 3:** implement (LocationService `getCurrentPosition({ enableHighAccuracy: true })`). **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: location helper with mobile GPS and browser fallback`.

---

### Task 8: LWC `journeyVisitCard`

**Files:**
- Create: `lwc/journeyVisitCard/` (js, html, css, js-meta.xml targets `lightning__RecordPage` (Event), `lightning__AppPage`; `@api recordId`, `@api visit`), `__tests__/journeyVisitCard.test.js`

**Interfaces:**
- Consumes: `getCurrentLocation`; `JourneyController.checkIn/checkOut`.
- Produces: fires `visitchange` (detail `{ eventId }`) after a successful check-in/out.

**Behaviour:** status Planned → "Check in" button; Checked In → summary textarea + "Check out"; Completed → read-only summary, time spent, leg km. On location error show the code-specific message (`DENIED`: how to enable location for the Salesforce app; `UNAVAILABLE`/`TIMEOUT`: move to open sky and Retry) and **do not call Apex**. `lowAccuracy` → warning toast after success. Buttons disabled while a call is in flight (prevents double tap).

- [ ] **Step 1: Failing Jest tests:** renders right button per status; location `DENIED` → Apex not called, message shown; success → `visitchange` fired; in-flight → button disabled; low accuracy → toast event.
- [ ] **Step 2–4:** fail → implement → pass (`npm run test:unit`).
- [ ] **Step 5:** Commit `feat: visit card with check-in and check-out`.

---

### Task 9: LWC day planner

**Files:**
- Create: `lwc/journeyPlanner/` (container: date nav, summary header, start/end day buttons; target `lightning__AppPage`, `lightning__Tab`, supported form factors Large and Small), `lwc/journeyTimeline/` (slots 07:00–21:00 in 30-min rows; cards positioned by start/end; overlap marker), `lwc/journeyEventForm/` (modal: subject, object type combobox from `objectOptions`, `lightning-record-picker` for that object, start/end), each with `__tests__/`

**Interfaces:**
- Consumes: `getDay`, `createVisit`, `rescheduleVisit`, `startDay`, `endDay`; `journeyVisitCard`; `getCurrentLocation`.
- Events: `journeyTimeline` fires `slotselect` `{ start: ISOString }` and `visitmove` `{ eventId, start, end }` (only emitted for status Planned).

- [ ] **Step 1: Failing Jest tests:** slot click opens form pre-filled start = slot, end = start + `defaultVisitMinutes`; `createVisit` returning overlaps shows warning listing their subjects with "Keep both" / "Change time"; overlapping cards render the warning marker; non-Planned card emits no `visitmove`; prev/next day reloads `getDay` with the new date; header shows `journey.Total_Km__c` and minutes as `Xh Ym`.
- [ ] **Step 2–4:** fail → implement → pass.
- [ ] **Step 5:** Commit `feat: day planner timeline with slot create and overlap warning`.

---

### Task 10: App, pages and admin config check

**Files:**
- Create: `lwc/journeyConfigCheck/` (+ test; lists `getConfigHealth()` results or "Configuration OK"), `applications/Journey_Planner.app-meta.xml`, `tabs/Journey_Planner.tab-meta.xml` (LWC tab for `journeyPlanner`), `tabs/Journey__c.tab-meta.xml`, `flexipages/Journey_Planner_Admin.flexipage-meta.xml`, `flexipages/Journey_Event_Record_Page.flexipage-meta.xml` (Event record page with `journeyVisitCard`); add app/tab visibility to both permission sets.

- [ ] **Step 1:** Jest test for `journeyConfigCheck` (renders issues list; renders OK state). Run → FAIL → implement → PASS.
- [ ] **Step 2 [org]:** deploy; assign `Journey_Planner_User` to a test user; manually verify on desktop: plan 3 visits, overlap warning, check-in/out (browser location), totals. Verify in the Salesforce mobile app on a phone: GPS check-in, denied permission shows block message.
- [ ] **Step 3:** Commit `feat: app, tabs, record page and configuration check`.

---

### Task 11: Packaging and release README

**Prerequisite:** Rudra has enabled Dev Hub, registered and linked the namespace (spec §11).

**Files:**
- Modify: `sfdx-project.json` (`"namespace": "<registered>"`, `packageAliases` filled by CLI), `README.md`

- [ ] **Step 1 [org]:** `sf package create --name "Journey Planner" --package-type Unlocked --path force-app --target-dev-hub devhub`.
- [ ] **Step 2 [org]:** full test run in a namespaced scratch org → PASS, org-wide coverage ≥ 90%.
- [ ] **Step 3 [org]:** `sf package version create --package "Journey Planner" --installation-key-bypass --code-coverage --wait 30`; then `sf package version promote`.
- [ ] **Step 4 [org]:** install the version in a fresh Developer Edition / scratch org via the install URL; assign permission set; smoke test planner + check-in.
- [ ] **Step 5:** README: install link, post-install steps (assign permission sets, add Event record page, enable "Allow Activities" for custom objects then add a `Journey_Object__mdt` row), how to add a new settings version (set previous version's Effective_To to the day before), privacy statement, screenshots/GIF placeholders filled by Rudra, roadmap (Tasks, calendar sync, road-distance provider).
- [ ] **Step 6:** Commit `chore: package v1.0 and install docs`; open PR to `main`.

/**
 * Protects visit data on Event (spec 8). Check-in and check-out data is written only by
 * JourneyService, which sets bypassGuard; holders of the Journey_Planner_Admin custom
 * permission may correct it, and their corrections to completed visits are re-stamped
 * and rolled up into the journey.
 */
public with sharing class EventTriggerHandler {
  public static final String MSG_CHECK_DATA = 'Check-in and check-out data can only be changed through the planner.';
  public static final String MSG_RESCHEDULE = 'A visit that has been checked in cannot be rescheduled.';
  public static final String MSG_DELETE = 'A visit that has been checked in cannot be deleted.';

  private static final List<SObjectField> GUARDED_FIELDS = new List<SObjectField>{
    Event.Check_In_Time__c,
    Event.Check_In_Latitude__c,
    Event.Check_In_Longitude__c,
    Event.Check_In_Accuracy_m__c,
    Event.Check_Out_Time__c,
    Event.Check_Out_Latitude__c,
    Event.Check_Out_Longitude__c,
    Event.Check_Out_Accuracy_m__c,
    Event.Visit_Status__c,
    Event.Time_Spent_Minutes__c,
    Event.Distance_From_Previous_Km__c
  };
  private static final List<SObjectField> SCHEDULE_FIELDS = new List<SObjectField>{
    Event.StartDateTime,
    Event.EndDateTime
  };

  /** True only around this handler's own recalculate call (its USER_MODE writes re-fire the trigger). */
  private static Boolean isRecalculating = false;
  private static Id adminCheckedFor;
  private static Boolean adminResult = false;

  public static void beforeUpdate(List<Event> records, Map<Id, Event> oldMap) {
    if (isSystemWrite()) {
      return;
    }
    for (Event rec : records) {
      Event old = oldMap.get(rec.Id);
      Boolean guarded = changed(rec, old, GUARDED_FIELDS);
      Boolean rescheduled =
        changed(rec, old, SCHEDULE_FIELDS) &&
        statusOf(old) != JourneyService.STATUS_PLANNED;
      if (!guarded && !rescheduled) {
        continue;
      }
      if (!isAdmin()) {
        rec.addError(guarded ? MSG_CHECK_DATA : MSG_RESCHEDULE);
      } else if (guarded) {
        restampMinutes(rec);
      }
    }
  }

  public static void beforeDelete(Map<Id, Event> oldMap) {
    if (isSystemWrite()) {
      return;
    }
    for (Event old : oldMap.values()) {
      if (statusOf(old) != JourneyService.STATUS_PLANNED && !isAdmin()) {
        old.addError(MSG_DELETE);
      }
    }
  }

  /**
   * Only an admin correction reaches here with guarded changes (others were stopped in
   * before update), so this rolls the corrected completed visits up into their journeys.
   */
  public static void afterUpdate(List<Event> records, Map<Id, Event> oldMap) {
    if (isSystemWrite()) {
      return;
    }
    Set<Id> journeyIds = new Set<Id>();
    for (Event rec : records) {
      Event old = oldMap.get(rec.Id);
      if (
        (statusOf(rec) == JourneyService.STATUS_COMPLETED ||
        statusOf(old) == JourneyService.STATUS_COMPLETED) &&
        changed(rec, old, GUARDED_FIELDS)
      ) {
        journeyIds.add(rec.Journey__c);
        journeyIds.add(old.Journey__c);
      }
    }
    journeyIds.remove(null);
    if (journeyIds.isEmpty()) {
      return;
    }
    isRecalculating = true;
    try {
      JourneyService.recalculate(journeyIds);
    } finally {
      isRecalculating = false;
    }
  }

  /** Service writes and this handler's own recalculation writes are never guarded or re-processed. */
  private static Boolean isSystemWrite() {
    return JourneyService.bypassGuard || isRecalculating;
  }

  /** Evaluated at most once per running user per transaction. */
  private static Boolean isAdmin() {
    if (adminCheckedFor != UserInfo.getUserId()) {
      adminResult = FeatureManagement.checkPermission('Journey_Planner_Admin');
      adminCheckedFor = UserInfo.getUserId();
    }
    return adminResult;
  }

  /** Runs in before update, so the corrected minutes are saved with the edit itself. */
  private static void restampMinutes(Event rec) {
    if (
      statusOf(rec) == JourneyService.STATUS_COMPLETED &&
      rec.Check_In_Time__c != null &&
      rec.Check_Out_Time__c != null
    ) {
      rec.Time_Spent_Minutes__c = Math.max(
        0,
        ((rec.Check_Out_Time__c.getTime() - rec.Check_In_Time__c.getTime()) /
          60000)
          .intValue()
      );
    }
  }

  private static Boolean changed(
    SObject current,
    SObject old,
    List<SObjectField> fields
  ) {
    for (SObjectField field : fields) {
      if (current.get(field) != old.get(field)) {
        return true;
      }
    }
    return false;
  }

  /** Events created before the package was installed have no status; treat them as Planned. */
  private static String statusOf(Event visit) {
    return visit.Visit_Status__c == null
      ? JourneyService.STATUS_PLANNED
      : visit.Visit_Status__c;
  }
}

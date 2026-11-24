/**
 * Aura-enabled entry points for the Journey Planner LWCs. Every method checks that the
 * running user holds a Journey Planner permission set, delegates to JourneyService /
 * JourneyConfig, and rethrows failures as AuraHandledException with a readable message.
 * Reads and writes of Event run in USER_MODE.
 */
public with sharing class JourneyController {
  private static final String DEFAULT_ICON = 'standard:event';
  private static final Integer FALLBACK_VISIT_MINUTES = 60;
  private static final String ADMIN_PERMISSION = 'Journey_Planner_Admin';
  private static final Set<String> USER_PERMISSION_SETS = new Set<String>{
    'Journey_Planner_User',
    'Journey_Planner_Admin'
  };

  public class DayView {
    @AuraEnabled
    public Journey__c journey;
    @AuraEnabled
    public List<VisitRow> visits = new List<VisitRow>();
    @AuraEnabled
    public List<ObjectOption> objectOptions = new List<ObjectOption>();
    @AuraEnabled
    public Integer defaultVisitMinutes;
  }

  public class VisitRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public Datetime startTime;
    @AuraEnabled
    public Datetime endTime;
    @AuraEnabled
    public Boolean allDay;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Id relatedId;
    @AuraEnabled
    public String relatedName;
    @AuraEnabled
    public String relatedObject;
    @AuraEnabled
    public String iconName;
    @AuraEnabled
    public Integer minutesSpent;
    @AuraEnabled
    public Decimal legKm;
    @AuraEnabled
    public String summary;
    @AuraEnabled
    public List<Id> overlapsWith = new List<Id>();
  }

  public class ObjectOption {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String relationField;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String iconName;
    @AuraEnabled
    public String displayField;
  }

  public class CreateResult {
    @AuraEnabled
    public Id eventId;
    @AuraEnabled
    public List<VisitRow> overlaps = new List<VisitRow>();
  }

  @AuraEnabled(cacheable=false)
  public static DayView getDay(Date dayDate) {
    try {
      requirePlannerUser();
      if (dayDate == null) {
        throw new JourneyException('Choose a date to show.');
      }
      Id userId = UserInfo.getUserId();
      Map<String, Journey_Object__mdt> configured = configuredObjects(dayDate);
      List<Event> events = eventsOn(userId, dayDate);
      List<Event> timedEvents = new List<Event>();
      for (Event ev : events) {
        if (ev.IsAllDayEvent != true) {
          timedEvents.add(ev);
        }
      }
      DayView view = new DayView();
      for (Event ev : events) {
        VisitRow row = toRow(ev, configured);
        if (ev.IsAllDayEvent != true) {
          for (
            Event other : OverlapChecker.overlaps(
              timedEvents,
              ev.StartDateTime,
              ev.EndDateTime,
              ev.Id
            )
          ) {
            row.overlapsWith.add(other.Id);
          }
        }
        view.visits.add(row);
      }
      view.journey = existingJourney(userId, dayDate);
      view.objectOptions = optionsFor(dayDate);
      Decimal minutes = JourneyConfig.settingFor(dayDate)
        .Default_Visit_Minutes__c;
      view.defaultVisitMinutes = minutes == null
        ? FALLBACK_VISIT_MINUTES
        : minutes.intValue();
      return view;
    } catch (Exception ex) {
      throw translate(ex);
    }
  }

  @AuraEnabled
  public static CreateResult createVisit(
    String subject,
    Datetime startTime,
    Datetime endTime,
    Id relatedId
  ) {
    try {
      requirePlannerUser();
      validateInterval(startTime, endTime);
      if (String.isBlank(subject)) {
        throw new JourneyException('Enter a subject for the visit.');
      }
      if (relatedId == null) {
        throw new JourneyException('Choose the record you are visiting.');
      }
      Date visitDate = JourneyService.localDate(startTime);
      String typeName = relatedId.getSobjectType()
        .getDescribe(SObjectDescribeOptions.DEFERRED)
        .getName();
      Journey_Object__mdt config = configuredObjects(visitDate)
        .get(typeName.toLowerCase());
      if (config == null) {
        throw new JourneyException(
          typeName +
            ' records cannot be used for visits on ' +
            String.valueOf(visitDate) +
            '. Ask your Salesforce admin to configure the object.'
        );
      }
      Event visit = new Event(
        OwnerId = UserInfo.getUserId(),
        Subject = subject.trim(),
        StartDateTime = startTime,
        EndDateTime = endTime
      );
      if (config.Relation_Field__c == 'WhoId') {
        visit.WhoId = relatedId;
      } else {
        visit.WhatId = relatedId;
      }
      Database.insert(visit, AccessLevel.USER_MODE);
      return resultFor(visit.Id, visitDate, startTime, endTime);
    } catch (Exception ex) {
      throw translate(ex);
    }
  }

  @AuraEnabled
  public static CreateResult rescheduleVisit(
    Id eventId,
    Datetime startTime,
    Datetime endTime
  ) {
    try {
      requirePlannerUser();
      validateInterval(startTime, endTime);
      List<Event> found = [
        SELECT Id, Visit_Status__c
        FROM Event
        WHERE Id = :eventId AND OwnerId = :UserInfo.getUserId()
        WITH USER_MODE
        LIMIT 1
      ];
      if (found.isEmpty()) {
        throw new JourneyException(
          'This visit was not found or is not yours to reschedule.'
        );
      }
      String status = found[0].Visit_Status__c == null
        ? JourneyService.STATUS_PLANNED
        : found[0].Visit_Status__c;
      if (status != JourneyService.STATUS_PLANNED) {
        throw new JourneyException(
          'Only a Planned visit can be rescheduled. This visit is ' +
            status +
            '.'
        );
      }
      Database.update(
        new Event(
          Id = eventId,
          StartDateTime = startTime,
          EndDateTime = endTime
        ),
        AccessLevel.USER_MODE
      );
      return resultFor(
        eventId,
        JourneyService.localDate(startTime),
        startTime,
        endTime
      );
    } catch (Exception ex) {
      throw translate(ex);
    }
  }

  @AuraEnabled
  public static JourneyService.CheckResult checkIn(
    Id eventId,
    LocationReading loc
  ) {
    try {
      requirePlannerUser();
      return JourneyService.checkIn(eventId, loc);
    } catch (Exception ex) {
      throw translate(ex);
    }
  }

  @AuraEnabled
  public static JourneyService.CheckResult checkOut(
    Id eventId,
    LocationReading loc,
    String summary
  ) {
    try {
      requirePlannerUser();
      return JourneyService.checkOut(eventId, loc, summary);
    } catch (Exception ex) {
      throw translate(ex);
    }
  }

  @AuraEnabled
  public static Journey__c startDay(Date d, LocationReading loc) {
    try {
      requirePlannerUser();
      return JourneyService.startDay(d, loc);
    } catch (Exception ex) {
      throw translate(ex);
    }
  }

  @AuraEnabled
  public static Journey__c endDay(Date d, LocationReading loc) {
    try {
      requirePlannerUser();
      return JourneyService.endDay(d, loc);
    } catch (Exception ex) {
      throw translate(ex);
    }
  }

  /** Gaps and overlaps in the setting versions from a year back to a year ahead. */
  @AuraEnabled(cacheable=false)
  public static List<String> getConfigHealth() {
    try {
      requirePlannerUser();
      if (!FeatureManagement.checkPermission(ADMIN_PERMISSION)) {
        throw new JourneyException(
          'The Journey Planner Admin permission is required to run the configuration check.'
        );
      }
      Date today = Date.today();
      return JourneyConfig.healthIssues(
        today.addDays(-365),
        today.addDays(365)
      );
    } catch (Exception ex) {
      throw translate(ex);
    }
  }

  // ---- helpers ----

  private static void requirePlannerUser() {
    Id userId = UserInfo.getUserId();
    Integer assigned = [
      SELECT COUNT()
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId AND PermissionSet.Name IN :USER_PERMISSION_SETS
      WITH SYSTEM_MODE
    ];
    if (assigned == 0) {
      throw new JourneyException(
        'You need the Journey Planner User permission set to use Journey Planner. Ask your Salesforce admin.'
      );
    }
  }

  private static void validateInterval(Datetime startTime, Datetime endTime) {
    if (startTime == null || endTime == null) {
      throw new JourneyException('A start and an end time are required.');
    }
    if (endTime <= startTime) {
      throw new JourneyException('The end time must be after the start time.');
    }
  }

  /** The user's timed events starting on the local date, plus all-day events on it. */
  private static List<Event> eventsOn(Id userId, Date dayDate) {
    Datetime dayStart = Datetime.newInstance(
      dayDate,
      Time.newInstance(0, 0, 0, 0)
    );
    Datetime dayEnd = Datetime.newInstance(
      dayDate.addDays(1),
      Time.newInstance(0, 0, 0, 0)
    );
    return [
      SELECT
        Id,
        Subject,
        StartDateTime,
        EndDateTime,
        IsAllDayEvent,
        Visit_Status__c,
        WhatId,
        What.Name,
        WhoId,
        Who.Name,
        Time_Spent_Minutes__c,
        Distance_From_Previous_Km__c,
        Meeting_Summary__c
      FROM Event
      WHERE
        OwnerId = :userId
        AND ((IsAllDayEvent = FALSE
        AND StartDateTime >= :dayStart
        AND StartDateTime < :dayEnd)
        OR (IsAllDayEvent = TRUE
        AND ActivityDate = :dayDate))
      WITH USER_MODE
      ORDER BY StartDateTime ASC, Id ASC
    ];
  }

  private static Journey__c existingJourney(Id userId, Date dayDate) {
    String key = String.valueOf(userId) + '_' + String.valueOf(dayDate);
    List<Journey__c> rows = [
      SELECT
        Id,
        Journey_Date__c,
        Total_Km__c,
        Total_Visit_Minutes__c,
        Visit_Count__c,
        Start_Time__c,
        End_Time__c,
        Applied_Road_Factor__c
      FROM Journey__c
      WHERE Unique_Key__c = :key
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /** Configured objects valid on the date, keyed by lower-case API name. */
  private static Map<String, Journey_Object__mdt> configuredObjects(Date d) {
    Map<String, Journey_Object__mdt> byName = new Map<String, Journey_Object__mdt>();
    for (Journey_Object__mdt row : JourneyConfig.objectsFor(d)) {
      byName.put(row.Object_API_Name__c.toLowerCase(), row);
    }
    return byName;
  }

  private static List<ObjectOption> optionsFor(Date d) {
    List<ObjectOption> options = new List<ObjectOption>();
    for (Journey_Object__mdt row : JourneyConfig.objectsFor(d)) {
      ObjectOption option = new ObjectOption();
      option.apiName = row.Object_API_Name__c;
      option.relationField = row.Relation_Field__c;
      option.label = labelFor(row.Object_API_Name__c);
      option.iconName = row.Icon_Name__c;
      option.displayField = row.Display_Field__c;
      options.add(option);
    }
    return options;
  }

  private static String labelFor(String apiName) {
    try {
      return Schema.describeSObjects(
          new List<String>{ apiName },
          SObjectDescribeOptions.DEFERRED
        )[0]
        .getLabel();
    } catch (Exception ex) {
      return apiName;
    }
  }

  private static VisitRow toRow(
    Event ev,
    Map<String, Journey_Object__mdt> configured
  ) {
    VisitRow row = new VisitRow();
    row.id = ev.Id;
    row.subject = ev.Subject;
    row.startTime = ev.StartDateTime;
    row.endTime = ev.EndDateTime;
    row.allDay = ev.IsAllDayEvent == true;
    row.status = ev.Visit_Status__c == null
      ? JourneyService.STATUS_PLANNED
      : ev.Visit_Status__c;
    row.iconName = DEFAULT_ICON;
    if (ev.WhatId != null) {
      row.relatedId = ev.WhatId;
      row.relatedName = ev.What?.Name;
    } else if (ev.WhoId != null) {
      row.relatedId = ev.WhoId;
      row.relatedName = ev.Who?.Name;
    }
    if (row.relatedId != null) {
      row.relatedObject = row.relatedId.getSobjectType()
        .getDescribe()
        .getName();
      Journey_Object__mdt config = configured.get(
        row.relatedObject.toLowerCase()
      );
      if (config != null && !String.isBlank(config.Icon_Name__c)) {
        row.iconName = config.Icon_Name__c;
      }
    }
    row.minutesSpent = ev.Time_Spent_Minutes__c == null
      ? null
      : ev.Time_Spent_Minutes__c.intValue();
    row.legKm = ev.Distance_From_Previous_Km__c;
    row.summary = ev.Meeting_Summary__c;
    return row;
  }

  /** Overlaps among the user's other visits on that day, for the warning dialog. */
  private static CreateResult resultFor(
    Id eventId,
    Date visitDate,
    Datetime startTime,
    Datetime endTime
  ) {
    CreateResult result = new CreateResult();
    result.eventId = eventId;
    Map<String, Journey_Object__mdt> configured = configuredObjects(visitDate);
    for (
      Event other : OverlapChecker.overlaps(
        eventsOn(UserInfo.getUserId(), visitDate),
        startTime,
        endTime,
        eventId
      )
    ) {
      result.overlaps.add(toRow(other, configured));
    }
    return result;
  }

  /** Wraps any failure in an AuraHandledException whose message the client can show. */
  private static AuraHandledException translate(Exception ex) {
    if (ex instanceof AuraHandledException) {
      return (AuraHandledException) ex;
    }
    String message;
    if (
      ex instanceof JourneyException || ex instanceof JourneyConfigException
    ) {
      message = ex.getMessage();
    } else if (ex instanceof DmlException) {
      DmlException dml = (DmlException) ex;
      message = dml.getNumDml() > 0 ? dml.getDmlMessage(0) : dml.getMessage();
    } else if (
      ex instanceof QueryException || ex instanceof System.NoAccessException
    ) {
      message =
        'You do not have access to the data needed for this action. ' +
        ex.getMessage();
    } else {
      message = 'Journey Planner hit an unexpected error: ' + ex.getMessage();
    }
    AuraHandledException wrapped = new AuraHandledException(message);
    wrapped.setMessage(message);
    return wrapped;
  }
}

/**
 * Core Journey Planner service: one Journey__c per user per day, visit check-in and
 * check-out with a hard location requirement, and bulk recalculation of leg distances
 * and journey totals using the road factor stamped on each journey (spec 7.3, 7.4).
 *
 * Reads run in USER_MODE. System-stamped fields are written in SYSTEM_MODE only after an
 * explicit ownership check, with bypassGuard set for the duration of the DML.
 */
public with sharing class JourneyService {
  public static final String STATUS_PLANNED = 'Planned';
  public static final String STATUS_CHECKED_IN = 'Checked In';
  public static final String STATUS_COMPLETED = 'Completed';
  /** Used when the setting's Road_Factor__c is blank (spec: road factor default 1.30). */
  public static final Decimal DEFAULT_ROAD_FACTOR = 1.30;

  private static final String LOCATION_REQUIRED = 'Location is required to check in. Enable location and retry.';
  private static final Set<String> LOCATION_SOURCES = new Set<String>{
    'Mobile GPS',
    'Browser'
  };

  @TestVisible
  private static DistanceCalculator calculator = new StraightLineDistanceCalculator();

  /** True while this service writes system-stamped fields; the Event trigger reads it. */
  @TestVisible
  public static Boolean bypassGuard = false;

  @TestVisible
  private static Datetime nowOverride;

  public class CheckResult {
    @AuraEnabled
    public Id eventId;
    @AuraEnabled
    public Id journeyId;
    @AuraEnabled
    public Boolean lowAccuracy;
    @AuraEnabled
    public Decimal legKm;
    @AuraEnabled
    public Integer minutesSpent;
  }

  /**
   * Returns the user's journey for the date, creating it (and stamping the configuration
   * version valid on that date) when it does not exist. Never re-stamps an existing journey.
   */
  public static Journey__c getOrCreateJourney(Id userId, Date journeyDate) {
    if (userId == null || journeyDate == null) {
      throw new JourneyException(
        'A user and a date are required for a journey.'
      );
    }
    assertRunningUser(userId);
    String key = String.valueOf(userId) + '_' + String.valueOf(journeyDate);
    Journey__c existing = findJourney(key);
    if (existing != null) {
      return existing;
    }
    Journey_Setting__mdt setting = JourneyConfig.settingFor(journeyDate);
    List<Journey__c> created = new List<Journey__c>{
      new Journey__c(
        OwnerId = userId,
        Journey_Date__c = journeyDate,
        Unique_Key__c = key,
        Applied_Setting__c = setting.DeveloperName,
        Applied_Road_Factor__c = setting.Road_Factor__c ?? DEFAULT_ROAD_FACTOR,
        Applied_Require_Summary__c = setting.Require_Summary_On_Checkout__c ==
          true
      )
    };
    Boolean previous = bypassGuard;
    bypassGuard = true;
    try {
      Database.upsert(
        created,
        Journey__c.Unique_Key__c,
        true,
        AccessLevel.SYSTEM_MODE
      );
    } finally {
      bypassGuard = previous;
    }
    return findJourney(key);
  }

  /** The calendar date of dt in the running user's time zone. */
  public static Date localDate(Datetime dt) {
    return Date.valueOf(
      dt.format('yyyy-MM-dd', UserInfo.getTimeZone().getID())
    );
  }

  public static CheckResult checkIn(Id eventId, LocationReading loc) {
    requireLocation(loc);
    Event visit = ownedVisit(eventId);
    String status = statusOf(visit);
    if (status != STATUS_PLANNED) {
      throw new JourneyException(
        'Only a Planned visit can be checked in. This visit is ' + status + '.'
      );
    }
    Id userId = UserInfo.getUserId();
    List<Event> open = [
      SELECT Id, Subject
      FROM Event
      WHERE
        OwnerId = :userId
        AND Visit_Status__c = :STATUS_CHECKED_IN
        AND Id != :eventId
      WITH USER_MODE
      LIMIT 1
    ];
    if (!open.isEmpty()) {
      throw new JourneyException(
        'Check out of "' +
          open[0].Subject +
          '" before checking in to another visit.'
      );
    }

    Datetime stamp = now();
    Journey__c journey = getOrCreateJourney(userId, localDate(stamp));
    systemUpdate(
      new List<SObject>{
        new Event(
          Id = visit.Id,
          Journey__c = journey.Id,
          Check_In_Time__c = stamp,
          Check_In_Latitude__c = loc.latitude,
          Check_In_Longitude__c = loc.longitude,
          Check_In_Accuracy_m__c = loc.accuracyMeters,
          Location_Source__c = loc.source,
          Visit_Status__c = STATUS_CHECKED_IN
        )
      }
    );

    CheckResult result = new CheckResult();
    result.eventId = visit.Id;
    result.journeyId = journey.Id;
    result.lowAccuracy = isLowAccuracy(loc, journey.Journey_Date__c);
    return result;
  }

  public static CheckResult checkOut(
    Id eventId,
    LocationReading loc,
    String summary
  ) {
    requireLocation(loc);
    Event visit = ownedVisit(eventId);
    String status = statusOf(visit);
    if (status != STATUS_CHECKED_IN) {
      throw new JourneyException(
        'Only a Checked In visit can be checked out. This visit is ' +
          status +
          '.'
      );
    }
    Datetime stamp = now();
    Journey__c journey = journeyForCheckOut(visit, stamp);
    if (journey.Applied_Require_Summary__c == true && String.isBlank(summary)) {
      throw new JourneyException(
        'A meeting summary is required to check out of this visit.'
      );
    }

    Integer minutes = 0;
    if (visit.Check_In_Time__c != null) {
      minutes = Math.max(
        0,
        ((stamp.getTime() - visit.Check_In_Time__c.getTime()) / 60000)
          .intValue()
      );
    }
    Event changes = new Event(
      Id = visit.Id,
      Journey__c = journey.Id,
      Check_Out_Time__c = stamp,
      Check_Out_Latitude__c = loc.latitude,
      Check_Out_Longitude__c = loc.longitude,
      Check_Out_Accuracy_m__c = loc.accuracyMeters,
      Time_Spent_Minutes__c = minutes,
      Visit_Status__c = STATUS_COMPLETED
    );
    if (!String.isBlank(summary)) {
      changes.Meeting_Summary__c = summary;
    }
    systemUpdate(new List<SObject>{ changes });
    recalculate(new Set<Id>{ journey.Id });

    Event saved = [
      SELECT Distance_From_Previous_Km__c
      FROM Event
      WHERE Id = :visit.Id
      WITH USER_MODE
    ];
    CheckResult result = new CheckResult();
    result.eventId = visit.Id;
    result.journeyId = journey.Id;
    result.lowAccuracy = isLowAccuracy(loc, journey.Journey_Date__c);
    result.legKm = saved.Distance_From_Previous_Km__c;
    result.minutesSpent = minutes;
    return result;
  }

  public static Journey__c startDay(Date d, LocationReading loc) {
    return stampDay(d, loc, true);
  }

  public static Journey__c endDay(Date d, LocationReading loc) {
    return stampDay(d, loc, false);
  }

  /**
   * Recomputes every completed visit's leg (in check-in order) and the totals of each
   * journey, using the journey's stamped road factor. Two queries; at most one DML per type and access mode.
   */
  public static void recalculate(Set<Id> journeyIds) {
    if (journeyIds == null || journeyIds.isEmpty()) {
      return;
    }
    List<Journey__c> journeys = [
      SELECT
        Id,
        OwnerId,
        Applied_Road_Factor__c,
        Start_Latitude__c,
        Start_Longitude__c,
        End_Latitude__c,
        End_Longitude__c
      FROM Journey__c
      WHERE Id IN :journeyIds
      WITH USER_MODE
    ];
    Map<Id, List<Event>> visitsByJourney = new Map<Id, List<Event>>();
    for (Journey__c j : journeys) {
      visitsByJourney.put(j.Id, new List<Event>());
    }
    for (Event v : [
      SELECT
        Id,
        OwnerId,
        Journey__c,
        Check_In_Time__c,
        Check_Out_Time__c,
        Check_In_Latitude__c,
        Check_In_Longitude__c,
        Check_Out_Latitude__c,
        Check_Out_Longitude__c,
        Time_Spent_Minutes__c
      FROM Event
      WHERE
        Journey__c IN :visitsByJourney.keySet()
        AND Visit_Status__c = :STATUS_COMPLETED
      WITH USER_MODE
      ORDER BY Check_In_Time__c ASC NULLS FIRST, Id ASC
    ]) {
      visitsByJourney.get(v.Journey__c).add(v);
    }

    // One list per type and mode, so each DML holds a single SObject type.
    WriteSet legs = new WriteSet();
    WriteSet totals = new WriteSet();
    for (Journey__c j : journeys) {
      List<Event> visits = visitsByJourney.get(j.Id);
      Decimal factor = j.Applied_Road_Factor__c ?? DEFAULT_ROAD_FACTOR;
      Decimal totalKm = 0;
      Decimal minutes = 0;
      for (Integer i = 0; i < visits.size(); i++) {
        Event v = visits[i];
        Event previous = previousVisit(visits, i);
        GeoPoint origin = previous == null
          ? point(j.Start_Latitude__c, j.Start_Longitude__c)
          : point(
              previous.Check_Out_Latitude__c,
              previous.Check_Out_Longitude__c
            );
        Decimal leg = legKm(
          origin,
          point(v.Check_In_Latitude__c, v.Check_In_Longitude__c),
          factor
        );
        totalKm += leg;
        minutes += v.Time_Spent_Minutes__c == null
          ? 0.0
          : v.Time_Spent_Minutes__c;
        legs.add(
          new Event(Id = v.Id, Distance_From_Previous_Km__c = leg),
          v.OwnerId
        );
      }
      Event finalVisit = lastCheckOut(visits);
      if (finalVisit != null) {
        totalKm += legKm(
          point(
            finalVisit.Check_Out_Latitude__c,
            finalVisit.Check_Out_Longitude__c
          ),
          point(j.End_Latitude__c, j.End_Longitude__c),
          factor
        );
      }
      totals.add(
        new Journey__c(
          Id = j.Id,
          Total_Km__c = totalKm.setScale(2),
          Total_Visit_Minutes__c = minutes,
          Visit_Count__c = visits.size()
        ),
        j.OwnerId
      );
    }
    legs.save();
    totals.save();
  }

  private static Journey__c stampDay(
    Date d,
    LocationReading loc,
    Boolean isStart
  ) {
    requireLocation(loc);
    Journey__c journey = getOrCreateJourney(UserInfo.getUserId(), d);
    assertRunningUser(journey.OwnerId);
    Journey__c changes = new Journey__c(Id = journey.Id);
    if (isStart) {
      changes.Start_Latitude__c = loc.latitude;
      changes.Start_Longitude__c = loc.longitude;
      changes.Start_Time__c = now();
    } else {
      changes.End_Latitude__c = loc.latitude;
      changes.End_Longitude__c = loc.longitude;
      changes.End_Time__c = now();
    }
    systemUpdate(new List<SObject>{ changes });
    recalculate(new Set<Id>{ journey.Id });
    return findJourney(journey.Unique_Key__c);
  }

  /** Latest completed visit that checked out before this visit checked in. */
  private static Event previousVisit(List<Event> visits, Integer index) {
    Datetime checkedInAt = visits[index].Check_In_Time__c;
    if (checkedInAt == null) {
      return null;
    }
    Event best = null;
    for (Integer i = 0; i < visits.size(); i++) {
      Datetime checkedOutAt = visits[i].Check_Out_Time__c;
      if (
        i != index &&
        checkedOutAt != null &&
        checkedOutAt < checkedInAt &&
        (best == null ||
        checkedOutAt > best.Check_Out_Time__c)
      ) {
        best = visits[i];
      }
    }
    return best;
  }

  private static Event lastCheckOut(List<Event> visits) {
    Event latest = null;
    for (Event v : visits) {
      if (
        v.Check_Out_Time__c != null &&
        (latest == null ||
        v.Check_Out_Time__c > latest.Check_Out_Time__c)
      ) {
        latest = v;
      }
    }
    return latest;
  }

  private static Decimal legKm(GeoPoint origin, GeoPoint dest, Decimal factor) {
    if (origin == null || dest == null) {
      return 0;
    }
    return (calculator.kmBetween(origin, dest) * factor)
      .setScale(2, System.RoundingMode.HALF_UP);
  }

  private static GeoPoint point(Decimal lat, Decimal lng) {
    return lat == null || lng == null ? null : new GeoPoint(lat, lng);
  }

  private static Journey__c journeyForCheckOut(Event visit, Datetime stamp) {
    if (visit.Journey__c == null) {
      Datetime checkedInAt = visit.Check_In_Time__c == null
        ? stamp
        : visit.Check_In_Time__c;
      return getOrCreateJourney(UserInfo.getUserId(), localDate(checkedInAt));
    }
    List<Journey__c> rows = [
      SELECT Id, Journey_Date__c, Applied_Require_Summary__c
      FROM Journey__c
      WHERE Id = :visit.Journey__c
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new JourneyException(
        'The journey for this visit was not found or is not accessible.'
      );
    }
    return rows[0];
  }

  private static Journey__c findJourney(String key) {
    List<Journey__c> rows = [
      SELECT
        Id,
        Name,
        OwnerId,
        Journey_Date__c,
        Unique_Key__c,
        Start_Latitude__c,
        Start_Longitude__c,
        Start_Time__c,
        End_Latitude__c,
        End_Longitude__c,
        End_Time__c,
        Total_Km__c,
        Total_Visit_Minutes__c,
        Visit_Count__c,
        Applied_Setting__c,
        Applied_Road_Factor__c,
        Applied_Require_Summary__c
      FROM Journey__c
      WHERE Unique_Key__c = :key
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static Event ownedVisit(Id eventId) {
    List<Event> rows = [
      SELECT Id, OwnerId, Subject, Visit_Status__c, Journey__c, Check_In_Time__c
      FROM Event
      WHERE Id = :eventId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new JourneyException(
        'This visit was not found or you do not have access to it.'
      );
    }
    if (rows[0].OwnerId != UserInfo.getUserId()) {
      throw new JourneyException(
        'You can only check in or out of your own visits.'
      );
    }
    return rows[0];
  }

  /** Events created before the package was installed have no status; treat them as Planned. */
  private static String statusOf(Event visit) {
    return visit.Visit_Status__c == null
      ? STATUS_PLANNED
      : visit.Visit_Status__c;
  }

  private static void requireLocation(LocationReading loc) {
    if (loc == null || loc.latitude == null || loc.longitude == null) {
      throw new JourneyException(LOCATION_REQUIRED);
    }
    if (loc.source != null && !LOCATION_SOURCES.contains(loc.source)) {
      throw new JourneyException('Unknown location source: ' + loc.source);
    }
  }

  private static void assertRunningUser(Id ownerId) {
    if (ownerId != UserInfo.getUserId()) {
      throw new JourneyException('You can only manage your own journeys.');
    }
  }

  /** Current resolve, not the stamp: the accuracy limit only drives a warning. */
  private static Boolean isLowAccuracy(LocationReading loc, Date journeyDate) {
    Decimal maxMeters = JourneyConfig.settingFor(journeyDate)
      .Max_Location_Accuracy_m__c;
    return loc.accuracyMeters != null &&
      maxMeters != null &&
      loc.accuracyMeters > maxMeters;
  }

  /** SYSTEM_MODE update; callers have verified the running user owns every record. */
  private static void systemUpdate(List<SObject> records) {
    if (records.isEmpty()) {
      return;
    }
    Boolean previous = bypassGuard;
    bypassGuard = true;
    try {
      Database.update(records, true, AccessLevel.SYSTEM_MODE);
    } finally {
      bypassGuard = previous;
    }
  }

  /**
   * Splits writes by ownership: the running user's records go through SYSTEM_MODE; anyone
   * else's (an admin recalculating another user's journey) run in USER_MODE, so the admin's
   * own FLS and sharing apply.
   */
  private class WriteSet {
    private final List<SObject> owned = new List<SObject>();
    private final List<SObject> others = new List<SObject>();

    public void add(SObject record, Id ownerId) {
      if (ownerId == UserInfo.getUserId()) {
        owned.add(record);
      } else {
        others.add(record);
      }
    }

    public void save() {
      systemUpdate(owned);
      if (!others.isEmpty()) {
        Database.update(others, true, AccessLevel.USER_MODE);
      }
    }
  }

  private static Datetime now() {
    return nowOverride == null ? Datetime.now() : nowOverride;
  }
}

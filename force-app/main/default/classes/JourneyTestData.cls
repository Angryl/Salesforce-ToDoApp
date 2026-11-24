/**
 * Test data factory for Journey Planner tests.
 */
@IsTest
public class JourneyTestData {
  public static final Decimal ROAD_FACTOR = 1.30;

  /**
   * One open-ended active setting (factor 1.30, no summary rule, accuracy limit 200 m).
   */
  public static Journey_Setting__mdt setting(
    String name,
    Date fromDate,
    Date toDate,
    Decimal roadFactor,
    Boolean requireSummary
  ) {
    return new Journey_Setting__mdt(
      DeveloperName = name,
      Effective_From__c = fromDate,
      Effective_To__c = toDate,
      Road_Factor__c = roadFactor,
      Require_Summary_On_Checkout__c = requireSummary,
      Default_Visit_Minutes__c = 60,
      Max_Location_Accuracy_m__c = 200,
      Is_Active__c = true
    );
  }

  public static void useDefaultSetting() {
    useSettings(
      new List<Journey_Setting__mdt>{
        setting('V1', Date.newInstance(2000, 1, 1), null, ROAD_FACTOR, false)
      }
    );
  }

  public static void useSettings(List<Journey_Setting__mdt> settings) {
    JourneyConfig.settingsOverride = settings;
  }

  public static User createUser() {
    return createUser('Asia/Kolkata');
  }

  /**
   * Inserts an active user with the Journey_Planner_User permission set. Runs as the
   * current user so the setup DML does not mix with later non-setup DML.
   */
  public static User createUser(String timeZoneSidKey) {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Standard User', 'System Administrator')
      ORDER BY Name ASC
      LIMIT 1
    ];
    String unique =
      String.valueOf(Datetime.now().getTime()) +
      String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User u = new User(
      ProfileId = profile.Id,
      Username = 'jp' + unique + '@journeyplanner.test',
      Email = 'jp' + unique + '@journeyplanner.test',
      LastName = 'Planner',
      FirstName = 'Journey',
      Alias = 'jp' + unique.right(6),
      TimeZoneSidKey = timeZoneSidKey,
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Journey_Planner_User'
        LIMIT 1
      ];
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = ps.Id
      );
    }
    return u;
  }

  public static Event plannedEvent(Id ownerId, String subject) {
    Datetime startAt = Datetime.now().addHours(1);
    return new Event(
      OwnerId = ownerId,
      Subject = subject,
      StartDateTime = startAt,
      EndDateTime = startAt.addHours(1),
      Visit_Status__c = 'Planned'
    );
  }

  public static List<Event> insertPlannedEvents(Id ownerId, Integer count) {
    List<Event> events = new List<Event>();
    for (Integer i = 0; i < count; i++) {
      events.add(plannedEvent(ownerId, 'Visit ' + i));
    }
    insert events;
    return events;
  }

  public static LocationReading location(
    Decimal lat,
    Decimal lng,
    Decimal accuracy
  ) {
    LocationReading loc = new LocationReading();
    loc.latitude = lat;
    loc.longitude = lng;
    loc.accuracyMeters = accuracy;
    loc.source = 'Mobile GPS';
    return loc;
  }

  public static LocationReading location() {
    return location(28.6139, 77.209, 20);
  }

  /**
   * Inserts one journey per date in a single DML, stamped like the service does (V1, 1.30).
   */
  public static List<Journey__c> insertJourneys(Id ownerId, List<Date> dates) {
    List<Journey__c> journeys = new List<Journey__c>();
    for (Date d : dates) {
      journeys.add(
        new Journey__c(
          OwnerId = ownerId,
          Journey_Date__c = d,
          Unique_Key__c = String.valueOf(ownerId) + '_' + String.valueOf(d),
          Applied_Setting__c = 'V1',
          Applied_Road_Factor__c = ROAD_FACTOR,
          Applied_Require_Summary__c = false
        )
      );
    }
    insertBypassingGuard(journeys);
    return journeys;
  }

  /**
   * Builds (does not insert) completed visits attached to a journey, one hour apart from
   * firstCheckIn, each lasting 30 minutes.
   */
  public static List<Event> completedVisits(
    Id ownerId,
    Id journeyId,
    Datetime firstCheckIn,
    Integer count
  ) {
    List<Event> events = new List<Event>();
    for (Integer i = 0; i < count; i++) {
      Datetime checkIn = firstCheckIn.addHours(i);
      events.add(
        new Event(
          OwnerId = ownerId,
          Subject = 'Completed ' + i,
          StartDateTime = checkIn,
          EndDateTime = checkIn.addMinutes(30),
          Visit_Status__c = 'Completed',
          Journey__c = journeyId,
          Check_In_Time__c = checkIn,
          Check_Out_Time__c = checkIn.addMinutes(30),
          Check_In_Latitude__c = 28.6,
          Check_In_Longitude__c = 77.2,
          Check_Out_Latitude__c = 28.6,
          Check_Out_Longitude__c = 77.2,
          Time_Spent_Minutes__c = 30
        )
      );
    }
    return events;
  }

  /** Inserts system-stamped test records the way the service writes them. */
  public static void insertBypassingGuard(List<SObject> records) {
    JourneyService.bypassGuard = true;
    try {
      insert records;
    } finally {
      JourneyService.bypassGuard = false;
    }
  }

  /**
   * Returns 10.000 km for every pair so leg totals are exact (10 x 1.30 = 13.00).
   */
  public class FixedDistanceCalculator implements DistanceCalculator {
    public Decimal kmBetween(GeoPoint a, GeoPoint b) {
      return 10.000;
    }
  }

  public static void useFixedCalculator() {
    JourneyService.calculator = new FixedDistanceCalculator();
  }
}

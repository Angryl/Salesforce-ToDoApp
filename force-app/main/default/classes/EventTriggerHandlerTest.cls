@IsTest
private class EventTriggerHandlerTest {
  private static Datetime at(Integer hour) {
    return Datetime.newInstance(Date.today(), Time.newInstance(hour, 0, 0, 0));
  }

  /** A checked-in visit written the way the service writes it (guard bypassed). */
  private static Event checkedInVisit(Id ownerId) {
    Event e = JourneyTestData.plannedEvent(ownerId, 'Checked in');
    e.Visit_Status__c = JourneyService.STATUS_CHECKED_IN;
    e.Check_In_Time__c = at(9);
    e.Check_In_Latitude__c = 28.6;
    e.Check_In_Longitude__c = 77.2;
    JourneyTestData.insertBypassingGuard(new List<Event>{ e });
    return e;
  }

  private static User createAdmin() {
    User admin = JourneyTestData.createUser();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Journey_Planner_Admin'
        LIMIT 1
      ];
      insert new PermissionSetAssignment(
        AssigneeId = admin.Id,
        PermissionSetId = ps.Id
      );
    }
    return admin;
  }

  private static void assertBlocked(
    DmlException caught,
    String expectedMessage
  ) {
    Assert.isNotNull(caught, 'Expected the Event trigger to block the change.');
    Assert.isTrue(
      caught.getMessage().contains(expectedMessage),
      'Unexpected message: ' + caught.getMessage()
    );
  }

  @IsTest
  static void userCannotEditCheckInLatitude() {
    User u = JourneyTestData.createUser();
    Event visit = checkedInVisit(u.Id);
    DmlException caught;
    System.runAs(u) {
      try {
        update new Event(Id = visit.Id, Check_In_Latitude__c = 10.5);
      } catch (DmlException e) {
        caught = e;
      }
    }
    assertBlocked(caught, EventTriggerHandler.MSG_CHECK_DATA);
    Assert.areEqual(
      28.6,
      [SELECT Check_In_Latitude__c FROM Event WHERE Id = :visit.Id]
      .Check_In_Latitude__c
    );
  }

  @IsTest
  static void userCannotRescheduleCheckedInVisit() {
    User u = JourneyTestData.createUser();
    Event visit = checkedInVisit(u.Id);
    DmlException caught;
    System.runAs(u) {
      try {
        update new Event(
          Id = visit.Id,
          StartDateTime = visit.StartDateTime.addHours(3),
          EndDateTime = visit.EndDateTime.addHours(3)
        );
      } catch (DmlException e) {
        caught = e;
      }
    }
    assertBlocked(caught, EventTriggerHandler.MSG_RESCHEDULE);
    Assert.areEqual(
      visit.StartDateTime,
      [SELECT StartDateTime FROM Event WHERE Id = :visit.Id].StartDateTime
    );
  }

  @IsTest
  static void userCannotDeleteCheckedInVisit() {
    User u = JourneyTestData.createUser();
    Event visit = checkedInVisit(u.Id);
    DmlException caught;
    System.runAs(u) {
      try {
        delete new Event(Id = visit.Id);
      } catch (DmlException e) {
        caught = e;
      }
    }
    assertBlocked(caught, EventTriggerHandler.MSG_DELETE);
    Assert.areEqual(1, [SELECT COUNT() FROM Event WHERE Id = :visit.Id]);
  }

  @IsTest
  static void userCanRescheduleAndDeletePlannedVisit() {
    User u = JourneyTestData.createUser();
    Event visit = JourneyTestData.insertPlannedEvents(u.Id, 2)[0];
    Datetime moved = visit.StartDateTime.addHours(2);
    System.runAs(u) {
      update new Event(
        Id = visit.Id,
        StartDateTime = moved,
        EndDateTime = moved.addHours(1)
      );
    }
    Assert.areEqual(
      moved,
      [SELECT StartDateTime FROM Event WHERE Id = :visit.Id].StartDateTime
    );
    System.runAs(u) {
      delete new Event(Id = visit.Id);
    }
    Assert.areEqual(0, [SELECT COUNT() FROM Event WHERE Id = :visit.Id]);
  }

  @IsTest
  static void serviceWritesPassWhileBypassIsSet() {
    User u = JourneyTestData.createUser();
    Event visit = checkedInVisit(u.Id);
    System.runAs(u) {
      JourneyService.bypassGuard = true;
      try {
        update new Event(Id = visit.Id, Check_In_Latitude__c = 11.25);
      } finally {
        JourneyService.bypassGuard = false;
      }
    }
    Assert.areEqual(
      11.25,
      [SELECT Check_In_Latitude__c FROM Event WHERE Id = :visit.Id]
      .Check_In_Latitude__c
    );
  }

  @IsTest
  static void adminEditOfCheckOutTimeRecalculatesJourneyMinutes() {
    User admin = createAdmin();
    System.runAs(admin) {
      Journey__c journey = JourneyTestData.insertJourneys(
        admin.Id,
        new List<Date>{ Date.today() }
      )[0];
      // Two completed visits of 30 minutes each, checked in at 08:00 and 09:00.
      List<Event> visits = JourneyTestData.completedVisits(
        admin.Id,
        journey.Id,
        at(8),
        2
      );
      JourneyTestData.insertBypassingGuard(visits);

      update new Event(
        Id = visits[0].Id,
        Check_Out_Time__c = at(8).addMinutes(90)
      );

      Event edited = [
        SELECT Time_Spent_Minutes__c
        FROM Event
        WHERE Id = :visits[0].Id
      ];
      Assert.areEqual(90, edited.Time_Spent_Minutes__c);
      Journey__c refreshed = [
        SELECT Total_Visit_Minutes__c, Visit_Count__c
        FROM Journey__c
        WHERE Id = :journey.Id
      ];
      Assert.areEqual(120, refreshed.Total_Visit_Minutes__c);
      Assert.areEqual(2, refreshed.Visit_Count__c);
    }
  }

  @IsTest
  static void bulkUpdateOf200PlannedEventsPasses() {
    User u = JourneyTestData.createUser();
    List<Event> events = JourneyTestData.insertPlannedEvents(u.Id, 200);
    Map<Id, Event> before = new Map<Id, Event>(
      [SELECT Id, StartDateTime, EndDateTime FROM Event WHERE Id IN :events]
    );
    Assert.areEqual(200, before.size());
    List<Event> moves = new List<Event>();
    for (Event e : before.values()) {
      moves.add(
        new Event(
          Id = e.Id,
          StartDateTime = e.StartDateTime.addHours(1),
          EndDateTime = e.EndDateTime.addHours(1)
        )
      );
    }
    System.runAs(u) {
      update moves;
    }
    List<Event> after = [
      SELECT Id, StartDateTime, EndDateTime
      FROM Event
      WHERE Id IN :before.keySet()
    ];
    Assert.areEqual(200, after.size());
    for (Event e : after) {
      Event original = before.get(e.Id);
      Assert.areEqual(original.StartDateTime.addHours(1), e.StartDateTime);
      Assert.areEqual(original.EndDateTime.addHours(1), e.EndDateTime);
    }
  }
}

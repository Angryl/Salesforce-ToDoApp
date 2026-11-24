@IsTest
private class JourneyServiceTest {
  private static final String LOCATION_REQUIRED = 'Location is required to check in. Enable location and retry.';

  private static Datetime at(Date d, Integer hour, Integer minute) {
    return Datetime.newInstance(d, Time.newInstance(hour, minute, 0, 0));
  }

  private static void assertKm(Decimal expected, Decimal actual, String msg) {
    Assert.isNotNull(actual, msg);
    Assert.areEqual(expected.setScale(2), actual.setScale(2), msg);
  }

  private static Journey__c journey(Id journeyId) {
    return [
      SELECT
        Id,
        OwnerId,
        Journey_Date__c,
        Unique_Key__c,
        Total_Km__c,
        Total_Visit_Minutes__c,
        Visit_Count__c,
        Applied_Setting__c,
        Applied_Road_Factor__c,
        Applied_Require_Summary__c
      FROM Journey__c
      WHERE Id = :journeyId
    ];
  }

  private static Event visit(Id eventId) {
    return [
      SELECT
        Id,
        Journey__c,
        Visit_Status__c,
        Check_In_Time__c,
        Check_In_Latitude__c,
        Check_In_Longitude__c,
        Check_In_Accuracy_m__c,
        Location_Source__c,
        Check_Out_Time__c,
        Time_Spent_Minutes__c,
        Distance_From_Previous_Km__c,
        Meeting_Summary__c
      FROM Event
      WHERE Id = :eventId
    ];
  }

  /** Checks in at hour:00 and out at hour:45 on the given day. */
  private static JourneyService.CheckResult visitAt(
    Id eventId,
    Date d,
    Integer hour
  ) {
    JourneyService.nowOverride = at(d, hour, 0);
    JourneyService.checkIn(eventId, JourneyTestData.location());
    JourneyService.nowOverride = at(d, hour, 45);
    return JourneyService.checkOut(eventId, JourneyTestData.location(), null);
  }

  @IsTest
  static void checkIn_stampsAndAttachesJourney() {
    JourneyTestData.useDefaultSetting();
    JourneyTestData.useFixedCalculator();
    User u = JourneyTestData.createUser();
    Event ev = JourneyTestData.insertPlannedEvents(u.Id, 1)[0];

    System.runAs(u) {
      Date day = Date.today();
      JourneyService.nowOverride = at(day, 10, 0);
      Test.startTest();
      JourneyService.CheckResult result = JourneyService.checkIn(
        ev.Id,
        JourneyTestData.location(28.6139, 77.209, 20)
      );
      Test.stopTest();

      Event saved = visit(ev.Id);
      Assert.areEqual('Checked In', saved.Visit_Status__c);
      Assert.areEqual(at(day, 10, 0), saved.Check_In_Time__c);
      Assert.areEqual(28.6139, saved.Check_In_Latitude__c.setScale(4));
      Assert.areEqual(77.209, saved.Check_In_Longitude__c.setScale(3));
      Assert.areEqual(20, saved.Check_In_Accuracy_m__c.intValue());
      Assert.areEqual('Mobile GPS', saved.Location_Source__c);
      Assert.isNotNull(saved.Journey__c, 'Visit must be attached to a journey');
      Assert.areEqual(result.journeyId, saved.Journey__c);
      Assert.areEqual(ev.Id, result.eventId);
      Assert.isFalse(result.lowAccuracy);

      Journey__c j = journey(saved.Journey__c);
      Assert.areEqual(day, j.Journey_Date__c);
      Assert.areEqual(u.Id, j.OwnerId);
      Assert.areEqual(
        String.valueOf(u.Id) + '_' + String.valueOf(day),
        j.Unique_Key__c
      );
      Assert.areEqual('V1', j.Applied_Setting__c);
      Assert.areEqual(1.30, j.Applied_Road_Factor__c.setScale(2));
      Assert.isFalse(j.Applied_Require_Summary__c);
    }
  }

  @IsTest
  static void checkIn_withoutLocation_throwsAndStampsNothing() {
    JourneyTestData.useDefaultSetting();
    User u = JourneyTestData.createUser();
    Event ev = JourneyTestData.insertPlannedEvents(u.Id, 1)[0];

    System.runAs(u) {
      LocationReading noLatitude = JourneyTestData.location(null, 77.209, 20);
      for (
        LocationReading loc : new List<LocationReading>{ null, noLatitude }
      ) {
        try {
          JourneyService.checkIn(ev.Id, loc);
          Assert.fail('Expected JourneyException');
        } catch (JourneyException e) {
          Assert.areEqual(LOCATION_REQUIRED, e.getMessage());
        }
      }

      Event saved = visit(ev.Id);
      Assert.areEqual('Planned', saved.Visit_Status__c);
      Assert.isNull(saved.Check_In_Time__c);
      Assert.isNull(saved.Check_In_Latitude__c);
      Assert.isNull(saved.Journey__c);
      Assert.areEqual(0, [SELECT COUNT() FROM Journey__c]);
    }
  }

  @IsTest
  static void checkIn_twice_throws() {
    JourneyTestData.useDefaultSetting();
    User u = JourneyTestData.createUser();
    Event ev = JourneyTestData.insertPlannedEvents(u.Id, 1)[0];

    System.runAs(u) {
      JourneyService.checkIn(ev.Id, JourneyTestData.location());
      try {
        JourneyService.checkIn(ev.Id, JourneyTestData.location());
        Assert.fail('Expected JourneyException');
      } catch (JourneyException e) {
        Assert.isTrue(e.getMessage().contains('Planned'), e.getMessage());
      }
    }
  }

  @IsTest
  static void checkIn_whileAnotherCheckedIn_throws() {
    JourneyTestData.useDefaultSetting();
    User u = JourneyTestData.createUser();
    List<Event> events = JourneyTestData.insertPlannedEvents(u.Id, 2);

    System.runAs(u) {
      JourneyService.checkIn(events[0].Id, JourneyTestData.location());
      try {
        JourneyService.checkIn(events[1].Id, JourneyTestData.location());
        Assert.fail('Expected JourneyException');
      } catch (JourneyException e) {
        Assert.isTrue(e.getMessage().contains('Visit 0'), e.getMessage());
      }
      Assert.areEqual('Planned', visit(events[1].Id).Visit_Status__c);
    }
  }

  @IsTest
  static void checkIn_notOwner_throws() {
    JourneyTestData.useDefaultSetting();
    User owner = JourneyTestData.createUser();
    User other = JourneyTestData.createUser();
    Event ev = JourneyTestData.insertPlannedEvents(owner.Id, 1)[0];

    System.runAs(other) {
      try {
        JourneyService.checkIn(ev.Id, JourneyTestData.location());
        Assert.fail('Expected JourneyException');
      } catch (JourneyException e) {
        Assert.isNotNull(e.getMessage());
      }
    }
    Assert.areEqual('Planned', visit(ev.Id).Visit_Status__c);
  }

  @IsTest
  static void getOrCreateJourney_isIdempotent() {
    JourneyTestData.useDefaultSetting();
    User u = JourneyTestData.createUser();

    System.runAs(u) {
      Date d = Date.newInstance(2026, 11, 23);
      Journey__c firstResult = JourneyService.getOrCreateJourney(u.Id, d);
      Journey__c secondResult = JourneyService.getOrCreateJourney(u.Id, d);

      Assert.areEqual(firstResult.Id, secondResult.Id);
      Assert.areEqual(1, [SELECT COUNT() FROM Journey__c]);
      Assert.areEqual(
        String.valueOf(u.Id) + '_2026-11-23',
        secondResult.Unique_Key__c
      );
    }
  }

  @IsTest
  static void checkOut_computesMinutesAndLeg() {
    JourneyTestData.useDefaultSetting();
    JourneyTestData.useFixedCalculator();
    User u = JourneyTestData.createUser();
    List<Event> events = JourneyTestData.insertPlannedEvents(u.Id, 3);

    System.runAs(u) {
      Date day = Date.today();
      Test.startTest();
      JourneyService.CheckResult r1 = visitAt(events[0].Id, day, 9);
      JourneyService.CheckResult r2 = visitAt(events[1].Id, day, 11);
      JourneyService.CheckResult r3 = visitAt(events[2].Id, day, 13);
      Test.stopTest();

      assertKm(0, r1.legKm, 'leg 1');
      assertKm(13.00, r2.legKm, 'leg 2');
      assertKm(13.00, r3.legKm, 'leg 3');
      Assert.areEqual(45, r1.minutesSpent);

      Event visitOne = visit(events[0].Id);
      Assert.areEqual('Completed', visitOne.Visit_Status__c);
      Assert.areEqual(45, visitOne.Time_Spent_Minutes__c.intValue());
      assertKm(0, visitOne.Distance_From_Previous_Km__c, 'stored leg 1');
      assertKm(
        13.00,
        visit(events[2].Id).Distance_From_Previous_Km__c,
        'stored leg 3'
      );

      Journey__c j = journey(r3.journeyId);
      assertKm(26.00, j.Total_Km__c, 'journey total');
      Assert.areEqual(3, j.Visit_Count__c.intValue());
      Assert.areEqual(135, j.Total_Visit_Minutes__c.intValue());
    }
  }

  @IsTest
  static void startAndEndDay_countFirstAndLastLegs() {
    JourneyTestData.useDefaultSetting();
    JourneyTestData.useFixedCalculator();
    User u = JourneyTestData.createUser();
    List<Event> events = JourneyTestData.insertPlannedEvents(u.Id, 2);

    System.runAs(u) {
      Date day = Date.today();
      Test.startTest();
      JourneyService.nowOverride = at(day, 8, 0);
      Journey__c started = JourneyService.startDay(
        day,
        JourneyTestData.location()
      );
      Assert.isNotNull(started.Start_Time__c);
      visitAt(events[0].Id, day, 9);
      visitAt(events[1].Id, day, 11);
      JourneyService.nowOverride = at(day, 18, 0);
      Journey__c ended = JourneyService.endDay(day, JourneyTestData.location());
      Test.stopTest();

      Assert.areEqual(started.Id, ended.Id);
      Assert.areEqual(at(day, 18, 0), ended.End_Time__c);
      assertKm(39.00, journey(ended.Id).Total_Km__c, 'start + 2 legs + end');
      assertKm(
        13.00,
        visit(events[0].Id).Distance_From_Previous_Km__c,
        'leg from start'
      );
    }
  }

  @IsTest
  static void startDay_withoutLocation_throws() {
    JourneyTestData.useDefaultSetting();
    User u = JourneyTestData.createUser();

    System.runAs(u) {
      try {
        JourneyService.startDay(Date.today(), null);
        Assert.fail('Expected JourneyException');
      } catch (JourneyException e) {
        Assert.areEqual(LOCATION_REQUIRED, e.getMessage());
      }
      Assert.areEqual(0, [SELECT COUNT() FROM Journey__c]);
    }
  }

  @IsTest
  static void blankRoadFactor_defaultsTo130() {
    JourneyTestData.useSettings(
      new List<Journey_Setting__mdt>{
        JourneyTestData.setting(
          'V1',
          Date.newInstance(2000, 1, 1),
          null,
          null,
          false
        )
      }
    );
    JourneyTestData.useFixedCalculator();
    User u = JourneyTestData.createUser();
    List<Event> events = JourneyTestData.insertPlannedEvents(u.Id, 2);

    System.runAs(u) {
      Date day = Date.today();
      visitAt(events[0].Id, day, 9);
      JourneyService.CheckResult secondVisit = visitAt(events[1].Id, day, 11);

      Journey__c j = journey(secondVisit.journeyId);
      Assert.areEqual(1.30, j.Applied_Road_Factor__c.setScale(2));
      assertKm(13.00, secondVisit.legKm, 'leg uses default factor 1.30');
      assertKm(13.00, j.Total_Km__c, 'total uses default factor 1.30');
    }
  }

  @IsTest
  static void requireSummary_enforcedFromStampedVersion() {
    Date epoch = Date.newInstance(2000, 1, 1);
    JourneyTestData.useSettings(
      new List<Journey_Setting__mdt>{
        JourneyTestData.setting('V1', epoch, null, 1.30, true)
      }
    );
    User u = JourneyTestData.createUser();
    Event ev = JourneyTestData.insertPlannedEvents(u.Id, 1)[0];

    System.runAs(u) {
      JourneyService.CheckResult checkedIn = JourneyService.checkIn(
        ev.Id,
        JourneyTestData.location()
      );
      Assert.isTrue(journey(checkedIn.journeyId).Applied_Require_Summary__c);

      // A newer configuration no longer requires a summary; the stamped journey still does.
      JourneyTestData.useSettings(
        new List<Journey_Setting__mdt>{
          JourneyTestData.setting('V2', epoch, null, 1.30, false)
        }
      );
      try {
        JourneyService.checkOut(ev.Id, JourneyTestData.location(), '  ');
        Assert.fail('Expected JourneyException');
      } catch (JourneyException e) {
        Assert.isTrue(e.getMessage().contains('summary'), e.getMessage());
      }
      Assert.areEqual('Checked In', visit(ev.Id).Visit_Status__c);

      JourneyService.checkOut(
        ev.Id,
        JourneyTestData.location(),
        'Agreed pricing'
      );
      Event saved = visit(ev.Id);
      Assert.areEqual('Completed', saved.Visit_Status__c);
      Assert.areEqual('Agreed pricing', saved.Meeting_Summary__c);
    }
  }

  @IsTest
  static void checkOut_whenNotCheckedIn_throws() {
    JourneyTestData.useDefaultSetting();
    User u = JourneyTestData.createUser();
    Event ev = JourneyTestData.insertPlannedEvents(u.Id, 1)[0];

    System.runAs(u) {
      try {
        JourneyService.checkOut(ev.Id, JourneyTestData.location(), null);
        Assert.fail('Expected JourneyException');
      } catch (JourneyException e) {
        Assert.isTrue(e.getMessage().contains('Checked In'), e.getMessage());
      }
      Assert.isNull(visit(ev.Id).Check_Out_Time__c);
    }
  }

  @IsTest
  static void newConfigVersion_doesNotChangePastJourney() {
    JourneyTestData.useDefaultSetting();
    JourneyTestData.useFixedCalculator();
    User u = JourneyTestData.createUser();
    List<Event> events = JourneyTestData.insertPlannedEvents(u.Id, 2);

    System.runAs(u) {
      Date day = Date.today();
      Date prevDay = day.addDays(-1);
      visitAt(events[0].Id, prevDay, 9);
      JourneyService.CheckResult lastResult = visitAt(
        events[1].Id,
        prevDay,
        11
      );
      assertKm(
        13.00,
        journey(lastResult.journeyId).Total_Km__c,
        'before new version'
      );

      JourneyTestData.useSettings(
        new List<Journey_Setting__mdt>{
          JourneyTestData.setting(
            'V1',
            Date.newInstance(2000, 1, 1),
            prevDay,
            1.30,
            false
          ),
          JourneyTestData.setting('V2', day, null, 1.50, false)
        }
      );
      JourneyService.recalculate(new Set<Id>{ lastResult.journeyId });

      Journey__c j = journey(lastResult.journeyId);
      assertKm(13.00, j.Total_Km__c, 'after new version');
      Assert.areEqual('V1', j.Applied_Setting__c);
      Assert.areEqual(1.30, j.Applied_Road_Factor__c.setScale(2));
    }
  }

  @IsTest
  static void localDate_usesUserTimeZone() {
    User u = JourneyTestData.createUser('Asia/Kolkata');

    System.runAs(u) {
      Assert.areEqual(
        Date.newInstance(2026, 11, 24),
        JourneyService.localDate(
          Datetime.newInstanceGmt(2026, 11, 23, 19, 0, 0)
        )
      );
    }
  }

  @IsTest
  static void recalculate_bulk200() {
    JourneyTestData.useDefaultSetting();
    JourneyTestData.useFixedCalculator();
    User u = JourneyTestData.createUser();

    System.runAs(u) {
      Date base = Date.newInstance(2026, 11, 1);
      List<Date> dates = new List<Date>{
        base,
        base.addDays(1),
        base.addDays(2),
        base.addDays(3)
      };
      List<Journey__c> journeys = JourneyTestData.insertJourneys(u.Id, dates);
      Set<Id> journeyIds = new Set<Id>();
      List<Event> visits = new List<Event>();
      for (Journey__c j : journeys) {
        journeyIds.add(j.Id);
        visits.addAll(
          JourneyTestData.completedVisits(
            u.Id,
            j.Id,
            at(j.Journey_Date__c, 0, 0),
            50
          )
        );
      }
      JourneyTestData.insertBypassingGuard(visits);
      Assert.areEqual(200, visits.size());

      Test.startTest();
      JourneyService.recalculate(journeyIds);
      Integer queries = Limits.getQueries();
      Integer dml = Limits.getDmlStatements();
      Test.stopTest();

      Assert.isTrue(queries <= 3, 'SOQL used: ' + queries);
      Assert.isTrue(dml <= 4, 'DML used: ' + dml);
      for (Journey__c j : [
        SELECT Total_Km__c, Total_Visit_Minutes__c, Visit_Count__c
        FROM Journey__c
        WHERE Id IN :journeyIds
      ]) {
        assertKm(637.00, j.Total_Km__c, '49 legs x 13.00');
        Assert.areEqual(50, j.Visit_Count__c.intValue());
        Assert.areEqual(1500, j.Total_Visit_Minutes__c.intValue());
      }
    }
  }

  @IsTest
  static void lowAccuracy_flaggedNotBlocked() {
    JourneyTestData.useDefaultSetting();
    User u = JourneyTestData.createUser();
    Event ev = JourneyTestData.insertPlannedEvents(u.Id, 1)[0];

    System.runAs(u) {
      JourneyService.CheckResult checkedIn = JourneyService.checkIn(
        ev.Id,
        JourneyTestData.location(28.6139, 77.209, 500)
      );
      Assert.isTrue(checkedIn.lowAccuracy);
      Assert.areEqual('Checked In', visit(ev.Id).Visit_Status__c);

      JourneyService.CheckResult checkedOut = JourneyService.checkOut(
        ev.Id,
        JourneyTestData.location(28.6139, 77.209, 50),
        null
      );
      Assert.isFalse(checkedOut.lowAccuracy);
      Assert.areEqual('Completed', visit(ev.Id).Visit_Status__c);
    }
  }
}

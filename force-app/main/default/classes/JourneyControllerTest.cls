@IsTest
private class JourneyControllerTest {
  private static final Date DAY = Date.newInstance(2026, 6, 10);

  private static Datetime at(Integer hour, Integer minute) {
    return Datetime.newInstance(DAY, Time.newInstance(hour, minute, 0, 0));
  }

  private static Event timed(
    Id ownerId,
    String subject,
    Datetime s,
    Datetime e
  ) {
    return new Event(
      OwnerId = ownerId,
      Subject = subject,
      StartDateTime = s,
      EndDateTime = e
    );
  }

  private static Journey_Object__mdt objectRow(
    String apiName,
    String relationField,
    Decimal sortOrder
  ) {
    return new Journey_Object__mdt(
      DeveloperName = apiName + '_row',
      Object_API_Name__c = apiName,
      Relation_Field__c = relationField,
      Display_Field__c = 'Name',
      Icon_Name__c = 'standard:' + apiName.toLowerCase(),
      Sort_Order__c = sortOrder,
      Effective_From__c = Date.newInstance(2000, 1, 1),
      Is_Active__c = true
    );
  }

  private static void configure() {
    JourneyTestData.useDefaultSetting();
    JourneyConfig.objectsOverride = new List<Journey_Object__mdt>{
      objectRow('Account', 'WhatId', 1),
      objectRow('Lead', 'WhoId', 2)
    };
  }

  private static User userWithoutPermissionSet() {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Standard User', 'System Administrator')
      ORDER BY Name ASC
      LIMIT 1
    ];
    String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User u = new User(
      ProfileId = p.Id,
      Username = 'np' + unique + '@journeyplanner.test',
      Email = 'np' + unique + '@journeyplanner.test',
      LastName = 'NoPerms',
      Alias = 'np' + unique.left(6),
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert u;
    return u;
  }

  /** User in the runner's time zone so at() and the controller agree on the day. */
  private static User runnerUser() {
    return JourneyTestData.createUser(UserInfo.getTimeZone().getID());
  }

  private static User adminUser() {
    User u = runnerUser();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Journey_Planner_Admin'
        LIMIT 1
      ];
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = ps.Id
      );
    }
    return u;
  }

  private static String messageOf(AuraHandledException ex) {
    return ex.getMessage();
  }

  // ---- OverlapChecker (pure, no DML) ----

  @IsTest
  static void touchingIntervalsDoNotOverlap() {
    List<Event> day = new List<Event>{
      timed(null, 'Morning', at(10, 0), at(11, 0))
    };
    Assert.isTrue(
      OverlapChecker.overlaps(day, at(11, 0), at(12, 0), null).isEmpty(),
      'Starting exactly when another ends is not an overlap'
    );
    Assert.isTrue(
      OverlapChecker.overlaps(day, at(9, 0), at(10, 0), null).isEmpty(),
      'Ending exactly when another starts is not an overlap'
    );
  }

  @IsTest
  static void partialAndContainedIntervalsOverlap() {
    List<Event> day = new List<Event>{
      timed(null, 'Morning', at(10, 0), at(11, 0))
    };
    Assert.areEqual(
      1,
      OverlapChecker.overlaps(day, at(10, 30), at(11, 30), null).size(),
      'Partial overlap'
    );
    Assert.areEqual(
      1,
      OverlapChecker.overlaps(day, at(10, 15), at(10, 45), null).size(),
      'New interval inside existing'
    );
    Assert.areEqual(
      1,
      OverlapChecker.overlaps(day, at(9, 0), at(12, 0), null).size(),
      'New interval containing existing'
    );
  }

  @IsTest
  static void allDayAndExcludedEventsAreIgnored() {
    Event allDay = timed(null, 'Holiday', at(0, 0), at(23, 59));
    allDay.IsAllDayEvent = true;
    Event self = timed(null, 'Self', at(10, 0), at(11, 0));
    self.Id = '00U000000000001EAA';
    List<Event> day = new List<Event>{ allDay, self };
    Assert.isTrue(
      OverlapChecker.overlaps(day, at(10, 0), at(11, 0), self.Id).isEmpty(),
      'All-day event and the excluded event are both ignored'
    );
    Assert.areEqual(
      1,
      OverlapChecker.overlaps(day, at(10, 0), at(11, 0), null).size(),
      'Without exclusion only the timed event counts'
    );
  }

  // ---- getDay ----

  @IsTest
  static void getDayReturnsVisitsSortedWithOverlapIds() {
    configure();
    User u = runnerUser();
    Account acc = new Account(Name = 'Acme Traders', OwnerId = u.Id);
    insert acc;
    Event late = timed(u.Id, 'Late', at(15, 0), at(16, 0));
    Event first = timed(u.Id, 'First', at(10, 0), at(11, 0));
    first.WhatId = acc.Id;
    Event second = timed(u.Id, 'Second', at(10, 30), at(11, 30));
    Event otherDay = timed(
      u.Id,
      'Tomorrow',
      at(10, 0).addDays(1),
      at(11, 0).addDays(1)
    );
    insert new List<Event>{ late, first, second, otherDay };

    JourneyController.DayView view;
    System.runAs(u) {
      view = JourneyController.getDay(DAY);
    }

    Assert.areEqual(3, view.visits.size(), 'Only the requested day');
    Assert.areEqual('First', view.visits[0].subject);
    Assert.areEqual('Second', view.visits[1].subject);
    Assert.areEqual('Late', view.visits[2].subject);
    Assert.areEqual(new List<Id>{ second.Id }, view.visits[0].overlapsWith);
    Assert.areEqual(new List<Id>{ first.Id }, view.visits[1].overlapsWith);
    Assert.isTrue(view.visits[2].overlapsWith.isEmpty());
    Assert.areEqual(acc.Id, view.visits[0].relatedId);
    Assert.areEqual('Acme Traders', view.visits[0].relatedName);
    Assert.areEqual('Account', view.visits[0].relatedObject);
    Assert.areEqual('standard:account', view.visits[0].iconName);
    Assert.areEqual('standard:event', view.visits[2].iconName, 'Fallback icon');
    Assert.isNull(view.journey, 'getDay never creates a journey');
    Assert.areEqual(60, view.defaultVisitMinutes);
    Assert.areEqual(2, view.objectOptions.size());
    Assert.areEqual('Account', view.objectOptions[0].apiName);
    Assert.areEqual('WhatId', view.objectOptions[0].relationField);
    Assert.areEqual('Account', view.objectOptions[0].label);
  }

  @IsTest
  static void getDayIncludesAllDayEventsAndExistingJourney() {
    configure();
    User u = runnerUser();
    Event allDay = new Event(
      OwnerId = u.Id,
      Subject = 'Offsite',
      IsAllDayEvent = true,
      ActivityDate = DAY
    );
    insert allDay;
    JourneyTestData.insertJourneys(u.Id, new List<Date>{ DAY });

    JourneyController.DayView view;
    System.runAs(u) {
      view = JourneyController.getDay(DAY);
    }
    Assert.areEqual(1, view.visits.size());
    Assert.isTrue(view.visits[0].allDay);
    Assert.isNotNull(view.journey, 'Existing journey is returned');
    Assert.areEqual(DAY, view.journey.Journey_Date__c);
  }

  @IsTest
  static void getDayWithoutPermissionSetThrowsReadableMessage() {
    configure();
    User u = userWithoutPermissionSet();
    Boolean thrown = false;
    System.runAs(u) {
      try {
        JourneyController.getDay(DAY);
      } catch (AuraHandledException ex) {
        thrown = true;
        Assert.isTrue(
          messageOf(ex).contains('Journey Planner User'),
          'Message names the permission set: ' + messageOf(ex)
        );
      }
    }
    Assert.isTrue(thrown, 'AuraHandledException expected');
  }

  @IsTest
  static void getDayShowsVisitCrossingMidnightOnBothDays() {
    configure();
    User u = runnerUser();
    Event overnight = timed(u.Id, 'Overnight', at(23, 0), at(1, 0).addDays(1));
    insert overnight;
    JourneyController.DayView first;
    JourneyController.DayView next;
    System.runAs(u) {
      first = JourneyController.getDay(DAY);
      next = JourneyController.getDay(DAY.addDays(1));
    }
    Assert.areEqual(1, first.visits.size(), 'Overnight is on its start day');
    Assert.areEqual('Overnight', first.visits[0].subject);
    Assert.areEqual(
      1,
      next.visits.size(),
      'Overnight carries into the next day'
    );
    Assert.areEqual('Overnight', next.visits[0].subject);
  }

  // ---- createVisit ----

  @IsTest
  static void createVisitOnLeadSetsWhoId() {
    configure();
    User u = runnerUser();
    Lead lead = new Lead(LastName = 'Rao', Company = 'Rao Co', OwnerId = u.Id);
    insert lead;
    JourneyController.CreateResult result;
    System.runAs(u) {
      result = JourneyController.createVisit(
        'Meet Rao',
        at(10, 0),
        at(11, 0),
        lead.Id
      );
    }
    Event saved = [
      SELECT Subject, WhoId, WhatId, OwnerId
      FROM Event
      WHERE Id = :result.eventId
    ];
    Assert.areEqual(lead.Id, saved.WhoId);
    Assert.isNull(saved.WhatId);
    Assert.areEqual(u.Id, saved.OwnerId);
    Assert.isTrue(result.overlaps.isEmpty());
  }

  @IsTest
  static void createVisitOnAccountSetsWhatIdAndReportsOverlap() {
    configure();
    User u = runnerUser();
    Account acc = new Account(Name = 'Acme', OwnerId = u.Id);
    insert acc;
    Event existing = timed(u.Id, 'Existing', at(10, 0), at(11, 0));
    insert existing;
    JourneyController.CreateResult result;
    System.runAs(u) {
      result = JourneyController.createVisit(
        'Meet Acme',
        at(10, 30),
        at(11, 30),
        acc.Id
      );
    }
    Event saved = [SELECT WhatId, WhoId FROM Event WHERE Id = :result.eventId];
    Assert.areEqual(acc.Id, saved.WhatId);
    Assert.isNull(saved.WhoId);
    Assert.areEqual(1, result.overlaps.size());
    Assert.areEqual(existing.Id, result.overlaps[0].id);
  }

  @IsTest
  static void createVisitOnUnconfiguredObjectThrowsReadableMessage() {
    configure();
    User u = runnerUser();
    Contact c = new Contact(LastName = 'Nobody', OwnerId = u.Id);
    insert c;
    Boolean thrown = false;
    System.runAs(u) {
      try {
        JourneyController.createVisit('Meet', at(10, 0), at(11, 0), c.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        Assert.isTrue(
          messageOf(ex).contains('Contact'),
          'Names the unsupported object: ' + messageOf(ex)
        );
      }
    }
    Assert.isTrue(thrown, 'AuraHandledException expected');
    Assert.areEqual(0, [SELECT COUNT() FROM Event WHERE Subject = 'Meet']);
  }

  @IsTest
  static void createVisitRejectsEndNotAfterStart() {
    configure();
    User u = runnerUser();
    Account acc = new Account(Name = 'Acme', OwnerId = u.Id);
    insert acc;
    Boolean thrown = false;
    System.runAs(u) {
      try {
        JourneyController.createVisit('Bad', at(11, 0), at(11, 0), acc.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        Assert.isTrue(messageOf(ex).contains('end'), messageOf(ex));
      }
    }
    Assert.isTrue(thrown, 'AuraHandledException expected');
  }

  // ---- rescheduleVisit ----

  @IsTest
  static void rescheduleMovesPlannedVisit() {
    configure();
    User u = runnerUser();
    Event visit = timed(u.Id, 'Move me', at(10, 0), at(11, 0));
    Event other = timed(u.Id, 'Other', at(14, 0), at(15, 0));
    insert new List<Event>{ visit, other };
    JourneyController.CreateResult result;
    System.runAs(u) {
      result = JourneyController.rescheduleVisit(
        visit.Id,
        at(14, 30),
        at(15, 30)
      );
    }
    Event saved = [
      SELECT StartDateTime, EndDateTime
      FROM Event
      WHERE Id = :visit.Id
    ];
    Assert.areEqual(at(14, 30), saved.StartDateTime);
    Assert.areEqual(at(15, 30), saved.EndDateTime);
    Assert.areEqual(1, result.overlaps.size());
    Assert.areEqual(other.Id, result.overlaps[0].id);
  }

  @IsTest
  static void rescheduleRejectsVisitThatIsNotPlanned() {
    configure();
    User u = runnerUser();
    Event visit = timed(u.Id, 'Started', at(10, 0), at(11, 0));
    visit.Visit_Status__c = 'Checked In';
    JourneyTestData.insertBypassingGuard(new List<Event>{ visit });
    Boolean thrown = false;
    System.runAs(u) {
      try {
        JourneyController.rescheduleVisit(visit.Id, at(12, 0), at(13, 0));
      } catch (AuraHandledException ex) {
        thrown = true;
        Assert.isTrue(messageOf(ex).contains('Planned'), messageOf(ex));
      }
    }
    Assert.isTrue(thrown, 'AuraHandledException expected');
    Assert.areEqual(
      at(10, 0),
      [SELECT StartDateTime FROM Event WHERE Id = :visit.Id].StartDateTime
    );
  }

  // ---- check-in / check-out wrappers ----

  @IsTest
  static void checkInWithoutLocationSurfacesReadableMessage() {
    configure();
    User u = runnerUser();
    Event visit = JourneyTestData.plannedEvent(u.Id, 'No GPS');
    insert visit;
    Boolean thrown = false;
    System.runAs(u) {
      try {
        JourneyController.checkIn(visit.Id, null);
      } catch (AuraHandledException ex) {
        thrown = true;
        Assert.isTrue(
          messageOf(ex).contains('Location is required'),
          messageOf(ex)
        );
      }
    }
    Assert.isTrue(thrown, 'AuraHandledException expected');
  }

  @IsTest
  static void checkInAndOutDelegateToService() {
    configure();
    User u = runnerUser();
    Event visit = JourneyTestData.plannedEvent(u.Id, 'Real visit');
    insert visit;
    JourneyService.CheckResult inResult;
    JourneyService.CheckResult outResult;
    System.runAs(u) {
      inResult = JourneyController.checkIn(
        visit.Id,
        JourneyTestData.location()
      );
      outResult = JourneyController.checkOut(
        visit.Id,
        JourneyTestData.location(),
        'Done'
      );
    }
    Assert.areEqual(visit.Id, inResult.eventId);
    Assert.areEqual(
      JourneyService.STATUS_COMPLETED,
      [SELECT Visit_Status__c FROM Event WHERE Id = :visit.Id].Visit_Status__c
    );
    Assert.areEqual(visit.Id, outResult.eventId);
  }

  @IsTest
  static void startAndEndDayReturnJourney() {
    configure();
    User u = runnerUser();
    Journey__c started;
    Journey__c ended;
    System.runAs(u) {
      started = JourneyController.startDay(DAY, JourneyTestData.location());
      ended = JourneyController.endDay(DAY, JourneyTestData.location());
    }
    Assert.areEqual(DAY, started.Journey_Date__c);
    Assert.areEqual(started.Id, ended.Id);
  }

  // ---- getConfigHealth ----

  @IsTest
  static void getConfigHealthWithoutAdminPermissionThrows() {
    configure();
    User u = runnerUser();
    Boolean thrown = false;
    System.runAs(u) {
      try {
        JourneyController.getConfigHealth();
      } catch (AuraHandledException ex) {
        thrown = true;
        Assert.isTrue(messageOf(ex).contains('Admin'), messageOf(ex));
      }
    }
    Assert.isTrue(thrown, 'AuraHandledException expected');
  }

  @IsTest
  static void getConfigHealthForAdminListsIssues() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      JourneyTestData.setting(
        'Late',
        Date.today().addDays(10),
        null,
        1.30,
        false
      )
    };
    User u = adminUser();
    List<String> issues;
    System.runAs(u) {
      issues = JourneyController.getConfigHealth();
    }
    Assert.isFalse(issues.isEmpty(), 'Gap before the only version is reported');
  }
}

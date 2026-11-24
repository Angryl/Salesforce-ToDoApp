@IsTest
private class JourneyConfigTest {
  private static Journey_Setting__mdt setting(
    String name,
    Date fromDate,
    Date toDate,
    Boolean isActive
  ) {
    return new Journey_Setting__mdt(
      DeveloperName = name,
      Effective_From__c = fromDate,
      Effective_To__c = toDate,
      Road_Factor__c = 1.3,
      Is_Active__c = isActive
    );
  }

  private static Journey_Object__mdt journeyObject(
    String apiName,
    Decimal sortOrder,
    Date fromDate,
    Date toDate,
    Boolean isActive
  ) {
    return new Journey_Object__mdt(
      DeveloperName = apiName + '_' + String.valueOf(sortOrder),
      Object_API_Name__c = apiName,
      Sort_Order__c = sortOrder,
      Effective_From__c = fromDate,
      Effective_To__c = toDate,
      Is_Active__c = isActive
    );
  }

  private static Boolean anyContains(List<String> messages, String fragment) {
    for (String message : messages) {
      if (message.contains(fragment)) {
        return true;
      }
    }
    return false;
  }

  @IsTest
  static void settingFor_picksVersionOnBoundaries() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      setting(
        'V1',
        Date.newInstance(2026, 1, 1),
        Date.newInstance(2026, 6, 30),
        true
      ),
      setting('V2', Date.newInstance(2026, 7, 1), null, true)
    };

    Assert.areEqual(
      'V1',
      JourneyConfig.settingFor(Date.newInstance(2026, 6, 30)).DeveloperName
    );
    Assert.areEqual(
      'V2',
      JourneyConfig.settingFor(Date.newInstance(2026, 7, 1)).DeveloperName
    );
    Assert.areEqual(
      'V1',
      JourneyConfig.settingFor(Date.newInstance(2026, 1, 1)).DeveloperName
    );
    Assert.areEqual(
      'V2',
      JourneyConfig.settingFor(Date.newInstance(2030, 12, 31)).DeveloperName
    );
  }

  @IsTest
  static void settingFor_gapThrows() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      setting(
        'V1',
        Date.newInstance(2026, 1, 1),
        Date.newInstance(2026, 6, 30),
        true
      ),
      setting('V2', Date.newInstance(2026, 7, 5), null, true)
    };

    try {
      JourneyConfig.settingFor(Date.newInstance(2026, 7, 2));
      Assert.fail('Expected JourneyConfigException for a configuration gap');
    } catch (JourneyConfigException e) {
      Assert.isTrue(
        e.getMessage().contains('2026-07-02'),
        'Message was: ' + e.getMessage()
      );
    }
  }

  @IsTest
  static void settingFor_beforeFirstVersionThrows() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      setting('V1', Date.newInstance(2026, 1, 1), null, true)
    };

    try {
      JourneyConfig.settingFor(Date.newInstance(2025, 12, 31));
      Assert.fail('Expected JourneyConfigException before the first version');
    } catch (JourneyConfigException e) {
      Assert.isTrue(
        e.getMessage().contains('2025-12-31'),
        'Message was: ' + e.getMessage()
      );
    }
  }

  @IsTest
  static void settingFor_overlapThrows() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      setting(
        'V1',
        Date.newInstance(2026, 1, 1),
        Date.newInstance(2026, 7, 1),
        true
      ),
      setting('V2', Date.newInstance(2026, 7, 1), null, true)
    };

    try {
      JourneyConfig.settingFor(Date.newInstance(2026, 7, 1));
      Assert.fail('Expected JourneyConfigException for overlapping versions');
    } catch (JourneyConfigException e) {
      Assert.isTrue(
        e.getMessage().contains('2026-07-01'),
        'Message was: ' + e.getMessage()
      );
    }
    // Outside the overlap the resolver still works.
    Assert.areEqual(
      'V1',
      JourneyConfig.settingFor(Date.newInstance(2026, 6, 30)).DeveloperName
    );
    Assert.areEqual(
      'V2',
      JourneyConfig.settingFor(Date.newInstance(2026, 7, 2)).DeveloperName
    );
  }

  @IsTest
  static void settingFor_ignoresInactive() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      setting('Old', Date.newInstance(2026, 1, 1), null, false),
      setting('Live', Date.newInstance(2026, 1, 1), null, true)
    };

    Assert.areEqual(
      'Live',
      JourneyConfig.settingFor(Date.newInstance(2026, 3, 3)).DeveloperName
    );

    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      setting('Old', Date.newInstance(2026, 1, 1), null, false)
    };
    try {
      JourneyConfig.settingFor(Date.newInstance(2026, 3, 3));
      Assert.fail(
        'Expected JourneyConfigException when only inactive records exist'
      );
    } catch (JourneyConfigException e) {
      Assert.isTrue(
        e.getMessage().contains('2026-03-03'),
        'Message was: ' + e.getMessage()
      );
    }
  }

  @IsTest
  static void settingFor_nullDateThrows() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>();
    try {
      JourneyConfig.settingFor(null);
      Assert.fail('Expected JourneyConfigException for a null date');
    } catch (JourneyConfigException e) {
      Assert.isNotNull(e.getMessage());
    }
  }

  @IsTest
  static void objectsFor_respectsDatesAndOrder() {
    JourneyConfig.objectsOverride = new List<Journey_Object__mdt>{
      journeyObject(
        'Opportunity',
        30,
        Date.newInstance(2026, 1, 1),
        null,
        true
      ),
      journeyObject('Account', 10, Date.newInstance(2026, 1, 1), null, true),
      journeyObject('Custom__c', 20, Date.newInstance(2026, 8, 1), null, true),
      journeyObject('Lead', 5, Date.newInstance(2026, 1, 1), null, false)
    };

    List<Journey_Object__mdt> before = JourneyConfig.objectsFor(
      Date.newInstance(2026, 7, 31)
    );
    Assert.areEqual(2, before.size());
    Assert.areEqual('Account', before[0].Object_API_Name__c);
    Assert.areEqual('Opportunity', before[1].Object_API_Name__c);

    List<Journey_Object__mdt> onDay = JourneyConfig.objectsFor(
      Date.newInstance(2026, 8, 1)
    );
    Assert.areEqual(3, onDay.size());
    Assert.areEqual('Account', onDay[0].Object_API_Name__c);
    Assert.areEqual('Custom__c', onDay[1].Object_API_Name__c);
    Assert.areEqual('Opportunity', onDay[2].Object_API_Name__c);
  }

  @IsTest
  static void objectsFor_effectiveToIsInclusive() {
    JourneyConfig.objectsOverride = new List<Journey_Object__mdt>{
      journeyObject(
        'Account',
        10,
        Date.newInstance(2026, 1, 1),
        Date.newInstance(2026, 3, 31),
        true
      )
    };

    Assert.areEqual(
      1,
      JourneyConfig.objectsFor(Date.newInstance(2026, 3, 31)).size()
    );
    Assert.areEqual(
      0,
      JourneyConfig.objectsFor(Date.newInstance(2026, 4, 1)).size()
    );
  }

  @IsTest
  static void objectsFor_duplicateObjectOnSameDateThrows() {
    JourneyConfig.objectsOverride = new List<Journey_Object__mdt>{
      journeyObject('Account', 10, Date.newInstance(2026, 1, 1), null, true),
      journeyObject('Account', 20, Date.newInstance(2026, 6, 1), null, true)
    };

    Assert.areEqual(
      1,
      JourneyConfig.objectsFor(Date.newInstance(2026, 5, 31)).size()
    );
    try {
      JourneyConfig.objectsFor(Date.newInstance(2026, 6, 1));
      Assert.fail('Expected JourneyConfigException for a duplicate object');
    } catch (JourneyConfigException e) {
      Assert.isTrue(
        e.getMessage().contains('Account'),
        'Message was: ' + e.getMessage()
      );
      Assert.isTrue(
        e.getMessage().contains('2026-06-01'),
        'Message was: ' + e.getMessage()
      );
    }
  }

  @IsTest
  static void healthIssues_reportsGapAndOverlap() {
    // V1 ends 31 Mar, V2 starts 5 Apr (gap 1-4 Apr), V2 ends 15 Jun, V3 starts 15 Jun (one day overlap).
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      setting(
        'V1',
        Date.newInstance(2026, 1, 1),
        Date.newInstance(2026, 3, 31),
        true
      ),
      setting(
        'V2',
        Date.newInstance(2026, 4, 5),
        Date.newInstance(2026, 6, 15),
        true
      ),
      setting('V3', Date.newInstance(2026, 6, 15), null, true)
    };

    List<String> issues = JourneyConfig.healthIssues(
      Date.newInstance(2026, 1, 1),
      Date.newInstance(2026, 12, 31)
    );

    Assert.areEqual(2, issues.size(), 'Issues: ' + String.join(issues, ' | '));
    Assert.isTrue(issues[0].contains('2026-04-01'), issues[0]);
    Assert.isTrue(issues[0].contains('no active setting'), issues[0]);
    Assert.isTrue(issues[1].contains('2026-06-15'), issues[1]);
    Assert.isTrue(issues[1].contains('2 active settings overlap'), issues[1]);
  }

  @IsTest
  static void healthIssues_cleanConfigurationReturnsEmpty() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      setting(
        'V1',
        Date.newInstance(2026, 1, 1),
        Date.newInstance(2026, 6, 30),
        true
      ),
      setting('V2', Date.newInstance(2026, 7, 1), null, true)
    };

    Assert.isTrue(
      JourneyConfig.healthIssues(
          Date.newInstance(2026, 1, 1),
          Date.newInstance(2027, 1, 1)
        )
        .isEmpty()
    );
  }

  @IsTest
  static void healthIssues_clipsToRangeAndDedupes() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>{
      setting('V1', Date.newInstance(2026, 7, 1), null, true)
    };

    // Range begins before the first version: the range start itself is reported, once.
    List<String> issues = JourneyConfig.healthIssues(
      Date.newInstance(2026, 6, 1),
      Date.newInstance(2026, 6, 1)
    );
    Assert.areEqual(1, issues.size(), 'Issues: ' + String.join(issues, ' | '));
    Assert.isTrue(anyContains(issues, '2026-06-01'));

    // Boundaries outside the range are not evaluated.
    List<String> later = JourneyConfig.healthIssues(
      Date.newInstance(2026, 8, 1),
      Date.newInstance(2026, 9, 1)
    );
    Assert.isTrue(later.isEmpty());
  }

  @IsTest
  static void healthIssues_invalidRangeThrows() {
    JourneyConfig.settingsOverride = new List<Journey_Setting__mdt>();
    try {
      JourneyConfig.healthIssues(
        Date.newInstance(2026, 2, 1),
        Date.newInstance(2026, 1, 1)
      );
      Assert.fail('Expected JourneyConfigException for an inverted range');
    } catch (JourneyConfigException e) {
      Assert.isNotNull(e.getMessage());
    }
  }

  @IsTest
  static void realPath_usesCustomMetadataWithoutOverrides() {
    // No overrides: exercises getAll() against the shipped records. Must not throw a SOQL/compile issue.
    JourneyConfig.settingsOverride = null;
    JourneyConfig.objectsOverride = null;
    List<Journey_Object__mdt> objects = JourneyConfig.objectsFor(
      Date.newInstance(2026, 6, 1)
    );
    Assert.isNotNull(objects);
    Assert.isNotNull(JourneyConfig.settingFor(Date.newInstance(2026, 6, 1)));
  }
}

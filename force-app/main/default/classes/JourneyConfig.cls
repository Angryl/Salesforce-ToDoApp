/**
 * Effective-dated resolver for Journey Planner configuration (Journey_Setting__mdt and
 * Journey_Object__mdt). Records are read with getAll() (no SOQL) and filtered in Apex.
 * Fails closed: a gap or an overlap for a date raises JourneyConfigException.
 */
public with sharing class JourneyConfig {
  @TestVisible
  private static List<Journey_Setting__mdt> settingsOverride;
  @TestVisible
  private static List<Journey_Object__mdt> objectsOverride;

  /**
   * Returns the single active setting valid on the given date.
   */
  public static Journey_Setting__mdt settingFor(Date d) {
    if (d == null) {
      throw new JourneyConfigException(
        'A date is required to resolve the Journey setting.'
      );
    }
    List<Journey_Setting__mdt> matches = settingsOn(d);
    if (matches.isEmpty()) {
      throw new JourneyConfigException(
        'No active Journey setting is valid on ' + String.valueOf(d) + '.'
      );
    }
    if (matches.size() > 1) {
      throw new JourneyConfigException(
        matches.size() +
          ' active Journey settings overlap on ' +
          String.valueOf(d) +
          '.'
      );
    }
    return matches[0];
  }

  /**
   * Returns the active objects valid on the given date, ordered by Sort_Order__c.
   */
  public static List<Journey_Object__mdt> objectsFor(Date d) {
    if (d == null) {
      throw new JourneyConfigException(
        'A date is required to resolve the Journey objects.'
      );
    }
    List<SortableObject> wrapped = new List<SortableObject>();
    Set<String> seen = new Set<String>();
    for (Journey_Object__mdt rec : allObjects()) {
      if (
        rec.Is_Active__c != true ||
        !isValidOn(rec.Effective_From__c, rec.Effective_To__c, d)
      ) {
        continue;
      }
      String key = String.valueOf(rec.Object_API_Name__c).toLowerCase();
      if (!seen.add(key)) {
        throw new JourneyConfigException(
          'Object ' +
            rec.Object_API_Name__c +
            ' is configured more than once on ' +
            String.valueOf(d) +
            '.'
        );
      }
      wrapped.add(new SortableObject(rec));
    }
    wrapped.sort();
    List<Journey_Object__mdt> result = new List<Journey_Object__mdt>();
    for (SortableObject item : wrapped) {
      result.add(item.record);
    }
    return result;
  }

  /**
   * Lists gaps and overlaps in the setting versions across the range. Only version boundary dates
   * (each From, To, To + 1, plus the range ends) are evaluated, clipped to the range.
   */
  public static List<String> healthIssues(Date fromDate, Date toDate) {
    if (fromDate == null || toDate == null || fromDate > toDate) {
      throw new JourneyConfigException(
        'A valid date range is required for the configuration check.'
      );
    }
    Set<Date> candidates = new Set<Date>{ fromDate, toDate };
    for (Journey_Setting__mdt rec : allSettings()) {
      if (rec.Is_Active__c != true) {
        continue;
      }
      candidates.add(rec.Effective_From__c);
      if (rec.Effective_To__c != null) {
        candidates.add(rec.Effective_To__c);
        candidates.add(rec.Effective_To__c.addDays(1));
      }
    }
    List<Date> dates = new List<Date>();
    for (Date candidate : candidates) {
      if (candidate != null && candidate >= fromDate && candidate <= toDate) {
        dates.add(candidate);
      }
    }
    dates.sort();

    List<String> issues = new List<String>();
    for (Date checkDate : dates) {
      Integer count = settingsOn(checkDate).size();
      if (count == 0) {
        issues.add(String.valueOf(checkDate) + ': no active setting');
      } else if (count > 1) {
        issues.add(
          String.valueOf(checkDate) + ': ' + count + ' active settings overlap'
        );
      }
    }
    return issues;
  }

  private static List<Journey_Setting__mdt> settingsOn(Date d) {
    List<Journey_Setting__mdt> matches = new List<Journey_Setting__mdt>();
    for (Journey_Setting__mdt rec : allSettings()) {
      if (
        rec.Is_Active__c == true &&
        isValidOn(rec.Effective_From__c, rec.Effective_To__c, d)
      ) {
        matches.add(rec);
      }
    }
    return matches;
  }

  private static Boolean isValidOn(
    Date effectiveFrom,
    Date effectiveTo,
    Date d
  ) {
    return effectiveFrom != null &&
      effectiveFrom <= d &&
      (effectiveTo == null ||
      effectiveTo >= d);
  }

  private static List<Journey_Setting__mdt> allSettings() {
    return settingsOverride != null
      ? settingsOverride
      : Journey_Setting__mdt.getAll().values();
  }

  private static List<Journey_Object__mdt> allObjects() {
    return objectsOverride != null
      ? objectsOverride
      : Journey_Object__mdt.getAll().values();
  }

  private class SortableObject implements Comparable {
    private final Journey_Object__mdt record;

    private SortableObject(Journey_Object__mdt record) {
      this.record = record;
    }

    public Integer compareTo(Object other) {
      SortableObject o = (SortableObject) other;
      Decimal mine = record.Sort_Order__c == null
        ? 999999999
        : record.Sort_Order__c;
      Decimal theirs = o.record.Sort_Order__c == null
        ? 999999999
        : o.record.Sort_Order__c;
      if (mine != theirs) {
        return mine < theirs ? -1 : 1;
      }
      return String.valueOf(record.Object_API_Name__c)
        .compareTo(String.valueOf(o.record.Object_API_Name__c));
    }
  }
}

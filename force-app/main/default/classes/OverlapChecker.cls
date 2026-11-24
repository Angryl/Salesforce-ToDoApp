/**
 * Finds timed events that overlap a proposed interval (spec 7.2). Touching intervals
 * (one ends exactly when the other starts) do not overlap. All-day events are ignored.
 */
public with sharing class OverlapChecker {
  public static List<Event> overlaps(
    List<Event> sameDay,
    Datetime s,
    Datetime e,
    Id excludeId
  ) {
    List<Event> result = new List<Event>();
    if (sameDay == null || s == null || e == null) {
      return result;
    }
    for (Event other : sameDay) {
      if (
        other.IsAllDayEvent == true ||
        (excludeId != null &&
        other.Id == excludeId) ||
        other.StartDateTime == null ||
        other.EndDateTime == null
      ) {
        continue;
      }
      if (s < other.EndDateTime && e > other.StartDateTime) {
        result.add(other);
      }
    }
    return result;
  }
}

public interface DistanceCalculator {
  /**
   * Straight-line (great-circle) distance in kilometres between two points,
   * rounded to 3 decimal places. No road factor is applied.
   * Throws IllegalArgumentException when either point, or its latitude or
   * longitude, is null.
   */
  Decimal kmBetween(GeoPoint a, GeoPoint b);
}

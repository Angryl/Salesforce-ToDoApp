public with sharing class StraightLineDistanceCalculator implements DistanceCalculator {
  public Decimal kmBetween(GeoPoint a, GeoPoint b) {
    assertValid(a);
    assertValid(b);
    Location origin = Location.newInstance(a.latitude, a.longitude);
    Location destination = Location.newInstance(b.latitude, b.longitude);
    Double km = origin.getDistance(destination, 'km');
    return ((Decimal) km).setScale(3);
  }

  private static void assertValid(GeoPoint p) {
    if (p == null || p.latitude == null || p.longitude == null) {
      throw new IllegalArgumentException(
        'GeoPoint must be non-null with latitude and longitude'
      );
    }
  }
}

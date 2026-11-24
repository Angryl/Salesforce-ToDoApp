public with sharing class GeoPoint {
  public Decimal latitude;
  public Decimal longitude;

  public GeoPoint(Decimal lat, Decimal lng) {
    this.latitude = lat;
    this.longitude = lng;
  }
}

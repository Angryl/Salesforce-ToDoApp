/**
 * A device location fix sent from the client with a check-in, check-out, start or end of day.
 * source is one of 'Mobile GPS' or 'Browser'.
 */
public with sharing class LocationReading {
  @AuraEnabled
  public Decimal latitude;
  @AuraEnabled
  public Decimal longitude;
  @AuraEnabled
  public Decimal accuracyMeters;
  @AuraEnabled
  public String source;
}

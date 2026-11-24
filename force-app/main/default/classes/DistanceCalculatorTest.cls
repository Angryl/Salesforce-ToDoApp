@IsTest
private class DistanceCalculatorTest {
  @IsTest
  static void equatorOneDegreeIsAboutOneHundredElevenKm() {
    DistanceCalculator calc = new StraightLineDistanceCalculator();

    Decimal result = calc.kmBetween(new GeoPoint(0, 0), new GeoPoint(0, 1));

    Assert.isTrue(
      Math.abs(result - 111.195) < 0.01,
      'Expected about 111.195 km but was ' + result
    );
  }

  @IsTest
  static void samePointIsZeroKm() {
    DistanceCalculator calc = new StraightLineDistanceCalculator();
    GeoPoint point = new GeoPoint(28.6139, 77.2090);

    Decimal result = calc.kmBetween(point, point);

    Assert.areEqual(0.000, result, 'Distance to the same point must be 0');
  }

  @IsTest
  static void nullFirstPointThrows() {
    DistanceCalculator calc = new StraightLineDistanceCalculator();
    Boolean thrown = false;
    try {
      calc.kmBetween(null, new GeoPoint(0, 1));
    } catch (IllegalArgumentException e) {
      thrown = true;
    }
    Assert.isTrue(thrown, 'A null point must throw IllegalArgumentException');
  }

  @IsTest
  static void nullSecondPointThrows() {
    DistanceCalculator calc = new StraightLineDistanceCalculator();
    Boolean thrown = false;
    try {
      calc.kmBetween(new GeoPoint(0, 0), null);
    } catch (IllegalArgumentException e) {
      thrown = true;
    }
    Assert.isTrue(thrown, 'A null point must throw IllegalArgumentException');
  }

  @IsTest
  static void nullLatitudeThrows() {
    DistanceCalculator calc = new StraightLineDistanceCalculator();
    Boolean thrown = false;
    try {
      calc.kmBetween(new GeoPoint(null, 0), new GeoPoint(0, 1));
    } catch (IllegalArgumentException e) {
      thrown = true;
    }
    Assert.isTrue(
      thrown,
      'A null latitude must throw IllegalArgumentException'
    );
  }
}

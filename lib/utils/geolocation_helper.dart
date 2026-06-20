import 'geolocation_helper_stub.dart'
    if (dart.library.html) 'geolocation_helper_web.dart' as impl;

abstract class GeolocationHelper {
  static Future<GPSCoordinates?> getCurrentLocation() {
    return impl.getCurrentLocation();
  }
}

class GPSCoordinates {
  final double latitude;
  final double longitude;
  GPSCoordinates(this.latitude, this.longitude);
}

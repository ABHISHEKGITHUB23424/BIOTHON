import 'dart:async';
import 'dart:html' as html;
import 'geolocation_helper.dart';

Future<GPSCoordinates?> getCurrentLocation() async {
  try {
    final geolocation = html.window.navigator.geolocation;
    if (geolocation != null) {
      final position = await geolocation.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 10),
      );
      final coords = position.coords;
      if (coords != null) {
        return GPSCoordinates(
          coords.latitude?.toDouble() ?? 0.0,
          coords.longitude?.toDouble() ?? 0.0,
        );
      }
    }
  } catch (e) {
    print("Geolocation exception: $e");
  }
  return null;
}

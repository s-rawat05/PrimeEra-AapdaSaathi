import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// A latitude/longitude pair from the device.
class DevicePosition {
  const DevicePosition(this.lat, this.lng, {this.accuracyM});
  final double lat;
  final double lng;
  final double? accuracyM;
}

abstract class LocationProvider {
  /// Current position, or null if location is off/denied/unavailable. Never throws.
  Future<DevicePosition?> current({bool requestPermission = true});
}

class NoLocation implements LocationProvider {
  const NoLocation([this.position]);
  final DevicePosition? position;

  @override
  Future<DevicePosition?> current({bool requestPermission = true}) async => position;
}

class GeolocatorLocation implements LocationProvider {
  @override
  Future<DevicePosition?> current({bool requestPermission = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && requestPermission) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return DevicePosition(p.latitude, p.longitude, accuracyM: p.accuracy);
    } catch (e) {
      debugPrint('Location unavailable: $e');
      return null;
    }
  }
}

enum PermState { granted, denied, permanentlyDenied, unsupported }

enum AppPermission { notifications, location, camera, microphone }

/// Permission status/requests through permission_handler. Browsers report [PermState.unsupported].
abstract class PermissionGateway {
  Future<PermState> status(AppPermission p);
  Future<PermState> request(AppPermission p);
  Future<bool> openSettings();
}

class FakePermissionGateway implements PermissionGateway {
  final Map<AppPermission, PermState> states = {};
  final List<AppPermission> requested = [];

  @override
  Future<PermState> status(AppPermission p) async => states[p] ?? PermState.denied;

  @override
  Future<PermState> request(AppPermission p) async {
    requested.add(p);
    return states[p] = PermState.granted;
  }

  @override
  Future<bool> openSettings() async => true;
}

class HandlerPermissionGateway implements PermissionGateway {
  Permission _map(AppPermission p) => switch (p) {
        AppPermission.notifications => Permission.notification,
        AppPermission.location => Permission.locationWhenInUse,
        AppPermission.camera => Permission.camera,
        AppPermission.microphone => Permission.microphone,
      };

  PermState _conv(PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) return PermState.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return PermState.permanentlyDenied;
    return PermState.denied;
  }

  @override
  Future<PermState> status(AppPermission p) async {
    if (kIsWeb) return PermState.unsupported;
    try {
      return _conv(await _map(p).status);
    } catch (_) {
      return PermState.unsupported;
    }
  }

  @override
  Future<PermState> request(AppPermission p) async {
    if (kIsWeb) return PermState.unsupported;
    try {
      return _conv(await _map(p).request());
    } catch (_) {
      return PermState.unsupported;
    }
  }

  @override
  Future<bool> openSettings() async {
    if (kIsWeb) return false;
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }
}

/// Opens other apps: dialer, SMS, maps, browser. Injectable for tests.
abstract class ExternalLauncher {
  Future<bool> open(Uri uri);
}

class RecordingLauncher implements ExternalLauncher {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

class UrlExternalLauncher implements ExternalLauncher {
  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// Helpers that build the URIs we hand to other apps.
abstract final class Links {
  static Uri tel(String phone) => Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));

  /// `sms:` URI with a pre-filled body. The user still has to press Send in their SMS app.
  static Uri sms(String number, String body) => Uri(
        scheme: 'sms',
        path: number,
        query: 'body=${Uri.encodeComponent(body)}',
      );

  /// Google Maps universal URL: opens the maps app on Android, the website elsewhere.
  static Uri mapsDirections(double lat, double lng, {String travelMode = 'walking'}) => Uri.https(
        'www.google.com',
        '/maps/dir/',
        {'api': '1', 'destination': '$lat,$lng', 'travelmode': travelMode},
      );
}

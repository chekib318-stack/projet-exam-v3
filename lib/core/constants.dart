import 'package:flutter/material.dart';

// ── Brand colours ──────────────────────────────────────────────────────────
class AppColors {
  static const bg        = Color(0xFF080C18);
  static const surface   = Color(0xFF0F1625);
  static const card      = Color(0xFF141D2E);
  static const border    = Color(0xFF1E2D45);
  static const accent    = Color(0xFF00A8FF);
  static const accentDim = Color(0xFF0066AA);

  // Threat palette
  static const safe      = Color(0xFF00D68F);
  static const low       = Color(0xFF00D68F);
  static const medium    = Color(0xFFFFAA00);
  static const high      = Color(0xFFFF6B35);
  static const critical  = Color(0xFFFF2D55);

  // Text
  static const textPrimary   = Color(0xFFE8EDF5);
  static const textSecondary = Color(0xFF7A8BA8);
  static const textMuted     = Color(0xFF3D5068);
}

// ── BLE Service UUIDs that indicate cheating devices ──────────────────────
class BleUuids {
  // Audio profiles → earphones / headsets
  static const headset        = '00001108-0000-1000-8000-00805f9b34fb';
  static const audioSink      = '0000110b-0000-1000-8000-00805f9b34fb'; // A2DP
  static const audioSource    = '0000110a-0000-1000-8000-00805f9b34fb';
  static const handsFree      = '0000111e-0000-1000-8000-00805f9b34fb';
  static const handsFreeAudio = '0000111f-0000-1000-8000-00805f9b34fb';
  static const avrcpTarget    = '0000110c-0000-1000-8000-00805f9b34fb';
  // HID → smart glasses / input devices
  static const hid            = '00001812-0000-1000-8000-00805f9b34fb';
  // Generic access
  static const genericAccess  = '00001800-0000-1000-8000-00805f9b34fb';

  static const audioSet = {
    headset, audioSink, audioSource, handsFree, handsFreeAudio, avrcpTarget
  };
}

// ── Manufacturer IDs ───────────────────────────────────────────────────────
class ManufacturerId {
  static const apple   = 0x004C;
  static const samsung = 0x0075;
  static const xiaomi  = 0x038F;
  static const huawei  = 0x07D0;
  static const jabra   = 0x0306;
}

// ── Device name patterns that suggest cheating devices ────────────────────
const List<String> kEarbudsPatterns = [
  'airpods', 'buds', 'earbud', 'earphone', 'headset', 'headphone',
  'jabra', 'plantronics', 'bose', 'sony wf', 'sony wh', 'jbl',
  'galaxy buds', 'freebuds', 'dots', 'pods', 'flip', 'tune',
  'soundcore', 'anker', 'taotronics', 'mpow',
];

const List<String> kGlassesPatterns = [
  'glass', 'lunette', 'smart eye', 'ar ', 'vue', 'bose frames',
  'spectacles', 'focals', 'north ', 'vuzix',
];

const List<String> kWatchPatterns = [
  'watch', 'band ', 'fit ', 'gear ', 'galaxy watch', 'mi band',
  'amazfit', 'fitbit', 'garmin', 'versa', 'sense ',
];

const List<String> kPhonePatterns = [
  'iphone', 'samsung sm-', 'pixel ', 'oneplus', 'xiaomi', 'huawei',
  'oppo', 'vivo', 'redmi', 'poco', 'nokia', 'motorola',
];

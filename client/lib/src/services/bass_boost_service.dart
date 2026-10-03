import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available shelf frequencies (Hz) matching standard audio enhancements.
const bassBoostFrequencies = <double>[
  0,
  50,
  75,
  80,
  100,
  125,
  150,
  200,
  250,
];

/// Available boost levels (dB) matching standard Windows headphone settings.
const bassBoostLevels = <double>[
  0,
  3,
  6,
  9,
  12,
  15,
  18,
  21,
  24,
];

/// Configuration for bass boost DSP stage.
class BassBoostConfig {
  const BassBoostConfig({
    this.enabled = false,
    this.frequency = 150.0,
    this.gainDb = 0.0,
  });

  final bool enabled;
  final double frequency;
  final double gainDb;

  BassBoostConfig copyWith({
    bool? enabled,
    double? frequency,
    double? gainDb,
  }) => BassBoostConfig(
    enabled: enabled ?? this.enabled,
    frequency: frequency ?? this.frequency,
    gainDb: gainDb ?? this.gainDb,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'frequency': frequency,
    'gainDb': gainDb,
  };

  factory BassBoostConfig.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'] == true;
    final rawFreq = json['frequency'];
    final frequency = (rawFreq is num && rawFreq >= 0)
        ? rawFreq.toDouble()
        : 150.0;
    final rawGain = json['gainDb'];
    final gainDb = (rawGain is num && rawGain >= 0 && rawGain <= 24)
        ? rawGain.toDouble()
        : 0.0;

    return BassBoostConfig(
      enabled: enabled,
      frequency: frequency,
      gainDb: gainDb,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BassBoostConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          frequency == other.frequency &&
          gainDb == other.gainDb;

  @override
  int get hashCode => Object.hash(enabled, frequency, gainDb);
}

/// Manages global and per-playlist bass boost configurations.
class BassBoostService extends ChangeNotifier {
  static const _prefGlobalKey = 'maboy_bass_boost_global';
  static const _prefPlaylistsKey = 'maboy_bass_boost_playlists';

  BassBoostConfig _globalConfig = const BassBoostConfig();
  final Map<String, BassBoostConfig> _playlistConfigs = {};

  BassBoostConfig get globalConfig => _globalConfig;
  Map<String, BassBoostConfig> get playlistConfigs =>
      Map.unmodifiable(_playlistConfigs);

  /// Initializes configs from persistent storage.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final globalRaw = prefs.getString(_prefGlobalKey);
      if (globalRaw != null && globalRaw.isNotEmpty) {
        final decoded = jsonDecode(globalRaw);
        if (decoded is Map<String, dynamic>) {
          _globalConfig = BassBoostConfig.fromJson(decoded);
        }
      }

      final playlistsRaw = prefs.getString(_prefPlaylistsKey);
      if (playlistsRaw != null && playlistsRaw.isNotEmpty) {
        final decoded = jsonDecode(playlistsRaw);
        if (decoded is Map<String, dynamic>) {
          _playlistConfigs.clear();
          decoded.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              _playlistConfigs[key] = BassBoostConfig.fromJson(value);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load bass boost settings: $e');
    }
    notifyListeners();
  }

  /// Resolves the effective configuration for a given playlist.
  /// If the playlist has an explicit override, it is returned.
  /// Otherwise, falls back to the global configuration.
  BassBoostConfig resolveEffectiveConfig(String? playlistId) {
    if (playlistId != null && _playlistConfigs.containsKey(playlistId)) {
      return _playlistConfigs[playlistId]!;
    }
    return _globalConfig;
  }

  /// Whether a specific playlist has its own custom configuration.
  bool hasPlaylistOverride(String playlistId) =>
      _playlistConfigs.containsKey(playlistId);

  /// Returns the specific configuration for a playlist, or null if inheriting global.
  BassBoostConfig? getPlaylistConfig(String playlistId) =>
      _playlistConfigs[playlistId];

  /// Updates global bass boost settings.
  Future<void> setGlobalConfig(BassBoostConfig config) async {
    if (_globalConfig == config) return;
    _globalConfig = config;
    notifyListeners();
    await _saveGlobal();
  }

  /// Sets or updates a playlist-specific bass boost override.
  Future<void> setPlaylistConfig(
    String playlistId,
    BassBoostConfig config,
  ) async {
    _playlistConfigs[playlistId] = config;
    notifyListeners();
    await _savePlaylists();
  }

  /// Removes a playlist-specific override so it inherits global settings.
  Future<void> removePlaylistConfig(String playlistId) async {
    if (!_playlistConfigs.containsKey(playlistId)) return;
    _playlistConfigs.remove(playlistId);
    notifyListeners();
    await _savePlaylists();
  }

  Future<void> _saveGlobal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefGlobalKey, jsonEncode(_globalConfig.toJson()));
    } catch (e) {
      debugPrint('Failed to save global bass boost: $e');
    }
  }

  Future<void> _savePlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        for (final entry in _playlistConfigs.entries)
          entry.key: entry.value.toJson(),
      };
      await prefs.setString(_prefPlaylistsKey, jsonEncode(map));
    } catch (e) {
      debugPrint('Failed to save playlist bass boost: $e');
    }
  }
}

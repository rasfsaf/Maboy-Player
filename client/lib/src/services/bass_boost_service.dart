import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available shelf frequencies (Hz) matching standard audio enhancements.
const bassBoostFrequencies = <double>[
  20,
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

/// A pre-tuned bass enhancement preset.
class BassBoostPreset {
  const BassBoostPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.frequency,
    required this.gainDb,
  });

  final String id;
  final String name;
  final String description;
  final double frequency;
  final double gainDb;
}

/// Built-in acoustic presets tuned for different genres and listening tastes.
const builtInBassBoostPresets = <BassBoostPreset>[
  BassBoostPreset(
    id: 'subtle',
    name: 'Лёгкий',
    description: 'Мягкое и аккуратное утепление низов без гула (+6 dB на 100 Гц)',
    frequency: 100.0,
    gainDb: 6.0,
  ),
  BassBoostPreset(
    id: 'punch',
    name: 'Панч',
    description: 'Плотный акцент на ударной бочке для клубной музыки и рока (+9 dB на 80 Гц)',
    frequency: 80.0,
    gainDb: 9.0,
  ),
  BassBoostPreset(
    id: 'deep_sub',
    name: 'Глубокий саб',
    description: 'Массивный вибрирующий саб-бас и 808 для рэпа, фонка и трэпа (+12 dB на 50 Гц)',
    frequency: 50.0,
    gainDb: 12.0,
  ),
  BassBoostPreset(
    id: 'synth',
    name: 'Синт',
    description: 'Плотный текстурный бас для Synthwave, электроники и аналоговых синтов (+9 dB на 125 Гц)',
    frequency: 125.0,
    gainDb: 9.0,
  ),
  BassBoostPreset(
    id: 'mega_bass',
    name: 'Мега Бас',
    description: 'Максимальный напор для вечеринок и любителей мощных низов (+15 dB на 100 Гц)',
    frequency: 100.0,
    gainDb: 15.0,
  ),
  BassBoostPreset(
    id: 'warmth',
    name: 'Тёплый',
    description: 'Широкий объёмный бас для классического рока, джаза и ретро (+6 dB на 150 Гц)',
    frequency: 150.0,
    gainDb: 6.0,
  ),
];

/// Configuration for bass boost DSP stage.
class BassBoostConfig {
  const BassBoostConfig({
    this.enabled = false,
    this.frequency = 150.0,
    this.gainDb = 0.0,
    this.presetId,
  });

  final bool enabled;
  final double frequency;
  final double gainDb;
  final String? presetId;

  BassBoostConfig copyWith({
    bool? enabled,
    double? frequency,
    double? gainDb,
    String? presetId,
    bool clearPresetId = false,
  }) => BassBoostConfig(
    enabled: enabled ?? this.enabled,
    frequency: frequency != null
        ? (frequency < 20.0 ? 20.0 : frequency)
        : this.frequency,
    gainDb: gainDb ?? this.gainDb,
    presetId: clearPresetId ? null : (presetId ?? this.presetId),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'frequency': frequency,
    'gainDb': gainDb,
    if (presetId != null) 'presetId': presetId,
  };

  factory BassBoostConfig.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'] == true;
    final presetId = json['presetId'] as String?;
    final rawFreq = json['frequency'];
    final frequency = (rawFreq is num && rawFreq >= 20.0 && rawFreq <= 20000.0)
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
      presetId: presetId,
    );
  }

  /// Resolves the matching built-in preset or null if customized.
  BassBoostPreset? get matchingPreset {
    if (presetId != null) {
      for (final p in builtInBassBoostPresets) {
        if (p.id == presetId && p.frequency == frequency && p.gainDb == gainDb) {
          return p;
        }
      }
    }
    for (final p in builtInBassBoostPresets) {
      if (p.frequency == frequency && p.gainDb == gainDb) {
        return p;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BassBoostConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          frequency == other.frequency &&
          gainDb == other.gainDb &&
          presetId == other.presetId;

  @override
  int get hashCode => Object.hash(enabled, frequency, gainDb, presetId);
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

  /// Applies a preset to global or playlist scope.
  Future<void> applyPreset(BassBoostPreset preset, {String? playlistId}) async {
    final current = resolveEffectiveConfig(playlistId);
    final updated = current.copyWith(
      enabled: true,
      frequency: preset.frequency,
      gainDb: preset.gainDb,
      presetId: preset.id,
    );
    if (playlistId == null) {
      await setGlobalConfig(updated);
    } else {
      await setPlaylistConfig(playlistId, updated);
    }
  }

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

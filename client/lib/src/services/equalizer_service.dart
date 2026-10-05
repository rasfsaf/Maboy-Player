import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../equalizer.dart';

/// Configuration for the six-band equalizer in a specific scope (global or folder).
class EqualizerConfig {
  const EqualizerConfig({
    this.enabled = false,
    this.presetId = 'flat',
    this.gains = const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  });

  final bool enabled;
  final String presetId;
  final List<double> gains;

  EqualizerConfig copyWith({
    bool? enabled,
    String? presetId,
    List<double>? gains,
  }) =>
      EqualizerConfig(
        enabled: enabled ?? this.enabled,
        presetId: presetId ?? this.presetId,
        gains: gains != null ? List<double>.unmodifiable(gains) : this.gains,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'active_preset_id': presetId,
        'gains': gains,
      };

  factory EqualizerConfig.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'] == true;
    final presetId =
        '${json['presetId'] ?? json['active_preset_id'] ?? 'flat'}';
    final rawGains = json['gains'];
    List<double> gains = const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    if (rawGains is List && rawGains.length == equalizerFrequencies.length) {
      gains = rawGains
          .map((v) => (v is num ? v.toDouble() : 0.0).clamp(-12.0, 12.0))
          .toList(growable: false);
    }
    return EqualizerConfig(
      enabled: enabled,
      presetId: presetId,
      gains: gains,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EqualizerConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          presetId == other.presetId &&
          listEquals(gains, other.gains);

  @override
  int get hashCode => Object.hash(
        enabled,
        presetId,
        Object.hashAll(gains),
      );
}

/// Service managing global and per-folder equalizer configurations.
class EqualizerService extends ChangeNotifier {
  static const _prefFolderPrefix = 'maboy_equalizer_folders_';

  EqualizerConfig _globalConfig = const EqualizerConfig();
  final Map<String, EqualizerConfig> _folderConfigs = {};
  String? _account;

  EqualizerConfig get globalConfig => _globalConfig;
  Map<String, EqualizerConfig> get folderConfigs =>
      Map.unmodifiable(_folderConfigs);

  String? get _folderPrefsKey =>
      _account == null ? null : '$_prefFolderPrefix$_account';
  String? get _deviceStateKey =>
      _account == null ? null : 'equalizer_device_$_account';

  /// Initializes equalizer settings for the active account.
  Future<void> init(String? account) async {
    _account = account;
    final prefs = await SharedPreferences.getInstance();

    // 1. Load global config from legacy/standard key
    final devKey = _deviceStateKey;
    if (devKey != null) {
      final raw = prefs.getString(devKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            _globalConfig = EqualizerConfig.fromJson(decoded);
          }
        } catch (error) {
          debugPrint('Error loading global equalizer: $error');
        }
      }
    }

    // 2. Load folder overrides
    _folderConfigs.clear();
    final folderKey = _folderPrefsKey;
    if (folderKey != null) {
      final rawFolders = prefs.getString(folderKey);
      if (rawFolders != null && rawFolders.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawFolders);
          if (decoded is Map<String, dynamic>) {
            decoded.forEach((key, value) {
              if (value is Map<String, dynamic>) {
                _folderConfigs[key] = EqualizerConfig.fromJson(value);
              }
            });
          }
        } catch (error) {
          debugPrint('Error loading folder equalizers: $error');
        }
      }
    }

    notifyListeners();
  }

  /// Resolves the effective config for a given folder/playlist.
  /// If the folder has an override, it returns it; otherwise global.
  EqualizerConfig resolveEffectiveConfig(String? folderId) {
    if (folderId != null && _folderConfigs.containsKey(folderId)) {
      return _folderConfigs[folderId]!;
    }
    return _globalConfig;
  }

  /// Whether a given folder has an explicit equalizer override.
  bool hasFolderOverride(String folderId) =>
      _folderConfigs.containsKey(folderId);

  /// Returns the folder's config, or null if inheriting global.
  EqualizerConfig? getFolderConfig(String folderId) =>
      _folderConfigs[folderId];

  /// Updates global config and persists it.
  Future<void> setGlobalConfig(EqualizerConfig config) async {
    if (_globalConfig == config) return;
    _globalConfig = config;
    notifyListeners();
    await _saveGlobal();
  }

  /// Sets or updates a folder-specific override.
  Future<void> setFolderConfig(
    String folderId,
    EqualizerConfig config,
  ) async {
    _folderConfigs[folderId] = config;
    notifyListeners();
    await _saveFolders();
  }

  /// Removes a folder override so it inherits the global configuration.
  Future<void> removeFolderConfig(String folderId) async {
    if (!_folderConfigs.containsKey(folderId)) return;
    _folderConfigs.remove(folderId);
    notifyListeners();
    await _saveFolders();
  }

  /// Configures a specific scope (null for global, or folderId).
  Future<void> setScopeConfig(String? folderId, EqualizerConfig config) async {
    if (folderId == null) {
      await setGlobalConfig(config);
    } else {
      await setFolderConfig(folderId, config);
    }
  }

  /// Sets enabled state for a specific scope.
  Future<void> setScopeEnabled(String? folderId, bool enabled) async {
    final current = resolveEffectiveConfig(folderId);
    await setScopeConfig(folderId, current.copyWith(enabled: enabled));
  }

  /// Sets a preset for a specific scope.
  Future<void> setScopePreset(
    String? folderId,
    EqualizerPreset preset,
  ) async {
    final current = resolveEffectiveConfig(folderId);
    await setScopeConfig(
      folderId,
      current.copyWith(
        presetId: preset.id,
        gains: List<double>.from(preset.gains),
      ),
    );
  }

  /// Sets a specific band gain for a scope.
  Future<void> setScopeBand(
    String? folderId,
    int index,
    double gain,
  ) async {
    if (index < 0 || index >= equalizerFrequencies.length) return;
    final current = resolveEffectiveConfig(folderId);
    final updatedGains = List<double>.from(current.gains);
    updatedGains[index] = gain.clamp(-12.0, 12.0);
    await setScopeConfig(
      folderId,
      current.copyWith(
        presetId: 'manual',
        gains: updatedGains,
      ),
    );
  }

  /// Resets state on logout.
  Future<void> reset() async {
    _globalConfig = const EqualizerConfig();
    _folderConfigs.clear();
    _account = null;
    notifyListeners();
  }

  Future<void> _saveGlobal() async {
    final devKey = _deviceStateKey;
    if (devKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(devKey, jsonEncode(_globalConfig.toJson()));
    } catch (e) {
      debugPrint('Failed to save global equalizer: $e');
    }
  }

  Future<void> _saveFolders() async {
    final folderKey = _folderPrefsKey;
    if (folderKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        for (final entry in _folderConfigs.entries)
          entry.key: entry.value.toJson(),
      };
      await prefs.setString(folderKey, jsonEncode(map));
    } catch (e) {
      debugPrint('Failed to save folder equalizers: $e');
    }
  }
}

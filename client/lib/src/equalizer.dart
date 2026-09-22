import 'dart:math' as math;

const equalizerFrequencies = <double>[60, 150, 400, 1000, 2400, 15000];
const equalizerFrequencyLabels = <String>[
  '60Hz',
  '150Hz',
  '400Hz',
  '1kHz',
  '2.4kHz',
  '15kHz',
];

/// A portable six-band preset. Only custom presets are synchronized; device
/// playback state deliberately lives outside this model.
class EqualizerPreset {
  const EqualizerPreset({
    required this.id,
    required this.name,
    required this.gains,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final List<double> gains;
  final bool isBuiltIn;

  double get preampDb => -math.max(0.0, gains.fold<double>(0, math.max));

  Map<String, dynamic> toPayload() => {'id': id, 'name': name, 'gains': gains};

  factory EqualizerPreset.fromPayload(Map<String, dynamic> payload) {
    final id = '${payload['id'] ?? ''}'.trim();
    final name = '${payload['name'] ?? ''}'.trim();
    final rawGains = payload['gains'];
    if (id.isEmpty || name.isEmpty || name.length > 40 || rawGains is! List) {
      throw const FormatException('Некорректный пресет эквалайзера');
    }
    if (rawGains.length != equalizerFrequencies.length) {
      throw const FormatException('Пресет должен содержать шесть полос');
    }
    final gains = rawGains
        .map((value) {
          if (value is! num || !value.isFinite) {
            throw const FormatException('Усиление должно быть числом');
          }
          final gain = value.toDouble();
          if (gain < -12 || gain > 12) {
            throw const FormatException(
              'Усиление должно быть от -12 до +12 dB',
            );
          }
          return gain;
        })
        .toList(growable: false);
    return EqualizerPreset(id: id, name: name, gains: gains);
  }
}

/// The curves are conservative starting points for the fixed Spotify-style
/// bands. Automatic negative preamp keeps boosted presets from clipping.
const builtInEqualizerPresets = <EqualizerPreset>[
  EqualizerPreset(
    id: 'flat',
    name: 'Flat',
    gains: [0, 0, 0, 0, 0, 0],
    isBuiltIn: true,
  ),
  EqualizerPreset(
    id: 'metal_plus',
    name: 'Metal+',
    gains: [5.5, 2.5, -0.5, 0, 2, 3.5],
    isBuiltIn: true,
  ),
  EqualizerPreset(
    id: 'rock',
    name: 'Rock',
    gains: [3, 5, 1, 3, 1, 2],
    isBuiltIn: true,
  ),
  EqualizerPreset(
    id: 'pop',
    name: 'Pop',
    gains: [2, 2, 1, 0, 0, 4],
    isBuiltIn: true,
  ),
  EqualizerPreset(
    id: 'hip_hop',
    name: 'Hip-Hop',
    gains: [4, 3, 0, 1, 3, 1],
    isBuiltIn: true,
  ),
  EqualizerPreset(
    id: 'electronic',
    name: 'Electronic',
    gains: [5, 3, -1, 2, 4, 3],
    isBuiltIn: true,
  ),
  EqualizerPreset(
    id: 'jazz',
    name: 'Jazz',
    gains: [1, 2, 3, 1, 0, 1],
    isBuiltIn: true,
  ),
  EqualizerPreset(
    id: 'classical',
    name: 'Classical',
    gains: [-2, -2, -1, 3, 2, 2],
    isBuiltIn: true,
  ),
  EqualizerPreset(
    id: 'vocal',
    name: 'Vocal',
    gains: [-2, -1, 1, 4, 4, 2],
    isBuiltIn: true,
  ),
  EqualizerPreset(
    id: 'bass_boost',
    name: 'Bass Boost',
    gains: [6, 4, 2, 0, -1, -1],
    isBuiltIn: true,
  ),
];

EqualizerPreset builtInPreset(String id) => builtInEqualizerPresets.firstWhere(
  (preset) => preset.id == id,
  orElse: () => builtInEqualizerPresets.first,
);

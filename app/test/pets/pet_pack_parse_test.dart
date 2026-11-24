// PetPack.parse error paths (docs/design/pets.md §3): a broken pack is refused
// whole, with a FormatException naming what is wrong. The built-in packs these
// used to read are gone (copyright cleanup), so a minimal valid pack is spelled
// out here instead.

import 'package:dsh_app/pets/pet_pack.dart';
import 'package:dsh_app/pets/pet_state.dart' show PetStateName;
import 'package:flutter_test/flutter_test.dart';

/// A minimal schema-1 pack that parses.
Map<String, Object?> valid() => {
  'schema': 1,
  'id': 'test-pet',
  'name': 'Test Pet',
  'canvas': {'w': 10, 'h': 10},
  'anchor': {'x': 5, 'baseline': 9},
  'contentBox': {'x': 2, 'y': 4, 'w': 6, 'h': 5},
  'animations': {
    'idle': {
      'sheet': 'idle.png',
      'frameW': 6,
      'frameH': 5,
      'cols': 1,
      'box': {'x': 2, 'y': 4, 'w': 6, 'h': 5},
      'frames': [
        {'i': 0, 'ms': 100},
      ],
    },
  },
  'states': {
    'idle': ['idle'],
  },
};

void main() {
  test('a valid pack parses', () {
    final pack = PetPack.parse(valid());
    expect(pack.id, 'test-pet');
    expect(pack.animFor(PetStateName.idle).name, 'idle');
  });

  test('another schema is refused', () {
    expect(() => PetPack.parse({...valid(), 'schema': 2}), throwsFormatException);
  });

  test('a state naming a missing animation is refused', () {
    final json = valid();
    final states = {...json['states']! as Map<String, Object?>, 'error': ['nope']};
    expect(() => PetPack.parse({...json, 'states': states}), throwsFormatException);
  });

  test('a frame without a positive time is refused', () {
    final json = valid();
    final anims = {...json['animations']! as Map<String, Object?>};
    final idle = {...anims['idle']! as Map<String, Object?>};
    idle['frames'] = [
      {'i': 0, 'ms': 0},
    ];
    anims['idle'] = idle;
    expect(() => PetPack.parse({...json, 'animations': anims}), throwsFormatException);
  });

  test('a reaction naming a missing animation is refused', () {
    expect(
      () => PetPack.parse({...valid(), 'reactions': {'tapLeft': 'nope'}}),
      throwsFormatException,
    );
  });
}

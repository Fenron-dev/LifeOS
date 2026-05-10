import 'package:flutter/material.dart';

class ProductType {
  static const readyToEat        = 'readyToEat';
  static const needsCooking      = 'needsCooking';
  static const ingredient        = 'ingredient';
  static const device            = 'device';
  static const tool              = 'tool';
  static const consumableNonFood = 'consumable';
  static const general           = 'general';

  static const all = [
    readyToEat,
    needsCooking,
    ingredient,
    device,
    tool,
    consumableNonFood,
    general,
  ];

  static String labelDe(String id) => switch (id) {
        readyToEat        => 'Fertiggericht',
        needsCooking      => 'Muss gekocht werden',
        ingredient        => 'Zutat',
        device            => 'Gerät / Ausstattung',
        tool              => 'Werkzeug / Zubehör',
        consumableNonFood => 'Verbrauchsmaterial',
        general           => 'Allgemein / Sonstiges',
        _                 => id,
      };

  static IconData iconFor(String id) => switch (id) {
        readyToEat        => Icons.lunch_dining,
        needsCooking      => Icons.soup_kitchen,
        ingredient        => Icons.spa,
        device            => Icons.devices_other,
        tool              => Icons.build_outlined,
        consumableNonFood => Icons.inventory_2_outlined,
        general           => Icons.category_outlined,
        _                 => Icons.label_outline,
      };

  static Color colorFor(String id) => switch (id) {
        readyToEat        => Colors.orange,
        needsCooking      => Colors.deepOrange,
        ingredient        => Colors.green,
        device            => Colors.blueGrey,
        tool              => Colors.brown,
        consumableNonFood => Colors.teal,
        general           => Colors.grey,
        _                 => Colors.grey,
      };
}

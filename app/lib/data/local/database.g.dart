// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ActionGroupsTable extends ActionGroups
    with TableInfo<$ActionGroupsTable, ActionGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('folder'),
  );
  static const VerificationMeta _colorHexMeta = const VerificationMeta(
    'colorHex',
  );
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
    'color_hex',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#6366F1'),
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    icon,
    colorHex,
    orderIndex,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color_hex')) {
      context.handle(
        _colorHexMeta,
        colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta),
      );
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActionGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionGroup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      colorHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_hex'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ActionGroupsTable createAlias(String alias) {
    return $ActionGroupsTable(attachedDatabase, alias);
  }
}

class ActionGroup extends DataClass implements Insertable<ActionGroup> {
  final String id;
  final String name;
  final String icon;
  final String colorHex;
  final int orderIndex;
  final DateTime createdAt;
  const ActionGroup({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.orderIndex,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['color_hex'] = Variable<String>(colorHex);
    map['order_index'] = Variable<int>(orderIndex);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ActionGroupsCompanion toCompanion(bool nullToAbsent) {
    return ActionGroupsCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      colorHex: Value(colorHex),
      orderIndex: Value(orderIndex),
      createdAt: Value(createdAt),
    );
  }

  factory ActionGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionGroup(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'colorHex': serializer.toJson<String>(colorHex),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ActionGroup copyWith({
    String? id,
    String? name,
    String? icon,
    String? colorHex,
    int? orderIndex,
    DateTime? createdAt,
  }) => ActionGroup(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    colorHex: colorHex ?? this.colorHex,
    orderIndex: orderIndex ?? this.orderIndex,
    createdAt: createdAt ?? this.createdAt,
  );
  ActionGroup copyWithCompanion(ActionGroupsCompanion data) {
    return ActionGroup(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionGroup(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('colorHex: $colorHex, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, icon, colorHex, orderIndex, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionGroup &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.colorHex == this.colorHex &&
          other.orderIndex == this.orderIndex &&
          other.createdAt == this.createdAt);
}

class ActionGroupsCompanion extends UpdateCompanion<ActionGroup> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> icon;
  final Value<String> colorHex;
  final Value<int> orderIndex;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ActionGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionGroupsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.icon = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<ActionGroup> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<String>? colorHex,
    Expression<int>? orderIndex,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (colorHex != null) 'color_hex': colorHex,
      if (orderIndex != null) 'order_index': orderIndex,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionGroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? icon,
    Value<String>? colorHex,
    Value<int>? orderIndex,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ActionGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('colorHex: $colorHex, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionsTableTable extends ActionsTable
    with TableInfo<$ActionsTableTable, ActionsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 60,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('bolt'),
  );
  static const VerificationMeta _colorHexMeta = const VerificationMeta(
    'colorHex',
  );
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
    'color_hex',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#6366F1'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ActionType, String> actionType =
      GeneratedColumn<String>(
        'action_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ActionType>($ActionsTableTable.$converteractionType);
  static const VerificationMeta _commandTemplateMeta = const VerificationMeta(
    'commandTemplate',
  );
  @override
  late final GeneratedColumn<String> commandTemplate = GeneratedColumn<String>(
    'command_template',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requiresAdminMeta = const VerificationMeta(
    'requiresAdmin',
  );
  @override
  late final GeneratedColumn<bool> requiresAdmin = GeneratedColumn<bool>(
    'requires_admin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requires_admin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<TerminalType?, String>
  terminalType = GeneratedColumn<String>(
    'terminal_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<TerminalType?>($ActionsTableTable.$converterterminalTypen);
  static const VerificationMeta _showTerminalWindowMeta =
      const VerificationMeta('showTerminalWindow');
  @override
  late final GeneratedColumn<bool> showTerminalWindow = GeneratedColumn<bool>(
    'show_terminal_window',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("show_terminal_window" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pasteToActiveWindowMeta =
      const VerificationMeta('pasteToActiveWindow');
  @override
  late final GeneratedColumn<bool> pasteToActiveWindow = GeneratedColumn<bool>(
    'paste_to_active_window',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("paste_to_active_window" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _autoSubscribeBaseUrlMeta =
      const VerificationMeta('autoSubscribeBaseUrl');
  @override
  late final GeneratedColumn<String> autoSubscribeBaseUrl =
      GeneratedColumn<String>(
        'auto_subscribe_base_url',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _autoSubscribeHubPathMeta =
      const VerificationMeta('autoSubscribeHubPath');
  @override
  late final GeneratedColumn<String> autoSubscribeHubPath =
      GeneratedColumn<String>(
        'auto_subscribe_hub_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _autoSubscribeInvokeMethodMeta =
      const VerificationMeta('autoSubscribeInvokeMethod');
  @override
  late final GeneratedColumn<String> autoSubscribeInvokeMethod =
      GeneratedColumn<String>(
        'auto_subscribe_invoke_method',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _autoSubscribeJsonFieldMeta =
      const VerificationMeta('autoSubscribeJsonField');
  @override
  late final GeneratedColumn<String> autoSubscribeJsonField =
      GeneratedColumn<String>(
        'auto_subscribe_json_field',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _autoSubscribeAllowInvalidCertMeta =
      const VerificationMeta('autoSubscribeAllowInvalidCert');
  @override
  late final GeneratedColumn<bool> autoSubscribeAllowInvalidCert =
      GeneratedColumn<bool>(
        'auto_subscribe_allow_invalid_cert',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("auto_subscribe_allow_invalid_cert" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES action_groups (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    icon,
    colorHex,
    actionType,
    commandTemplate,
    requiresAdmin,
    terminalType,
    showTerminalWindow,
    pasteToActiveWindow,
    autoSubscribeBaseUrl,
    autoSubscribeHubPath,
    autoSubscribeInvokeMethod,
    autoSubscribeJsonField,
    autoSubscribeAllowInvalidCert,
    isFavorite,
    groupId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'actions_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color_hex')) {
      context.handle(
        _colorHexMeta,
        colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta),
      );
    }
    if (data.containsKey('command_template')) {
      context.handle(
        _commandTemplateMeta,
        commandTemplate.isAcceptableOrUnknown(
          data['command_template']!,
          _commandTemplateMeta,
        ),
      );
    }
    if (data.containsKey('requires_admin')) {
      context.handle(
        _requiresAdminMeta,
        requiresAdmin.isAcceptableOrUnknown(
          data['requires_admin']!,
          _requiresAdminMeta,
        ),
      );
    }
    if (data.containsKey('show_terminal_window')) {
      context.handle(
        _showTerminalWindowMeta,
        showTerminalWindow.isAcceptableOrUnknown(
          data['show_terminal_window']!,
          _showTerminalWindowMeta,
        ),
      );
    }
    if (data.containsKey('paste_to_active_window')) {
      context.handle(
        _pasteToActiveWindowMeta,
        pasteToActiveWindow.isAcceptableOrUnknown(
          data['paste_to_active_window']!,
          _pasteToActiveWindowMeta,
        ),
      );
    }
    if (data.containsKey('auto_subscribe_base_url')) {
      context.handle(
        _autoSubscribeBaseUrlMeta,
        autoSubscribeBaseUrl.isAcceptableOrUnknown(
          data['auto_subscribe_base_url']!,
          _autoSubscribeBaseUrlMeta,
        ),
      );
    }
    if (data.containsKey('auto_subscribe_hub_path')) {
      context.handle(
        _autoSubscribeHubPathMeta,
        autoSubscribeHubPath.isAcceptableOrUnknown(
          data['auto_subscribe_hub_path']!,
          _autoSubscribeHubPathMeta,
        ),
      );
    }
    if (data.containsKey('auto_subscribe_invoke_method')) {
      context.handle(
        _autoSubscribeInvokeMethodMeta,
        autoSubscribeInvokeMethod.isAcceptableOrUnknown(
          data['auto_subscribe_invoke_method']!,
          _autoSubscribeInvokeMethodMeta,
        ),
      );
    }
    if (data.containsKey('auto_subscribe_json_field')) {
      context.handle(
        _autoSubscribeJsonFieldMeta,
        autoSubscribeJsonField.isAcceptableOrUnknown(
          data['auto_subscribe_json_field']!,
          _autoSubscribeJsonFieldMeta,
        ),
      );
    }
    if (data.containsKey('auto_subscribe_allow_invalid_cert')) {
      context.handle(
        _autoSubscribeAllowInvalidCertMeta,
        autoSubscribeAllowInvalidCert.isAcceptableOrUnknown(
          data['auto_subscribe_allow_invalid_cert']!,
          _autoSubscribeAllowInvalidCertMeta,
        ),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActionsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      colorHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_hex'],
      )!,
      actionType: $ActionsTableTable.$converteractionType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}action_type'],
        )!,
      ),
      commandTemplate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_template'],
      ),
      requiresAdmin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_admin'],
      )!,
      terminalType: $ActionsTableTable.$converterterminalTypen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}terminal_type'],
        ),
      ),
      showTerminalWindow: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}show_terminal_window'],
      )!,
      pasteToActiveWindow: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}paste_to_active_window'],
      )!,
      autoSubscribeBaseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auto_subscribe_base_url'],
      ),
      autoSubscribeHubPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auto_subscribe_hub_path'],
      ),
      autoSubscribeInvokeMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auto_subscribe_invoke_method'],
      ),
      autoSubscribeJsonField: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auto_subscribe_json_field'],
      ),
      autoSubscribeAllowInvalidCert: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_subscribe_allow_invalid_cert'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ActionsTableTable createAlias(String alias) {
    return $ActionsTableTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ActionType, String, String> $converteractionType =
      const EnumNameConverter<ActionType>(ActionType.values);
  static JsonTypeConverter2<TerminalType, String, String>
  $converterterminalType = const EnumNameConverter<TerminalType>(
    TerminalType.values,
  );
  static JsonTypeConverter2<TerminalType?, String?, String?>
  $converterterminalTypen = JsonTypeConverter2.asNullable(
    $converterterminalType,
  );
}

class ActionsTableData extends DataClass
    implements Insertable<ActionsTableData> {
  final String id;
  final String name;
  final String? description;
  final String icon;
  final String colorHex;
  final ActionType actionType;

  /// Plantilla del comando/texto, con placeholders {{variable}}. Texto
  /// libre en vez de columnas por variable porque el numero de parametros
  /// es dinamico -- ver `ActionParameters`.
  final String? commandTemplate;
  final bool requiresAdmin;
  final TerminalType? terminalType;

  /// Solo aplica a `actionType = terminal`. Elige entre los DOS modos de
  /// ejecucion:
  ///
  /// - `false` (por defecto) -- **modo capturado**: el comando corre dentro
  ///   de NexoDeck, sin ninguna ventana, y su salida, su duracion y su codigo
  ///   de salida vuelven como notificacion. Es lo que se quiere casi siempre.
  /// - `true` -- **modo ventana**: abre una consola real y NO se captura
  ///   nada. Es la unica via para comandos interactivos (`ssh`, `npm init`),
  ///   que capturados se colgarian esperando un input que nadie puede
  ///   escribir.
  ///
  /// El default cambio a `false` en `schemaVersion 5`, junto con una
  /// migracion que dio vuelta las filas existentes: antes `true` queria decir
  /// "quiero ver la salida", y la forma de ver la salida ahora es el modo
  /// capturado, asi que darlas vuelta **preserva la intencion original**.
  final bool showTerminalWindow;

  /// Solo aplica a `actionType = clipboard`. Con `true`, ademas de copiar el
  /// texto, NexoDeck le devuelve el foco a la ventana que lo tenia antes del
  /// clic y le manda Ctrl+V.
  ///
  /// Existe porque sin esto una accion de portapapeles disparada con el mouse
  /// es, en la practica, media accion: el propio clic en el deck le saca el
  /// foco a la app de destino, asi que el texto queda copiado pero nunca
  /// llega a donde el usuario tenia el cursor. Ver `focus.rs` en
  /// `nexodeck-actions`.
  ///
  /// Por defecto `false`: copiar sin pegar sigue siendo un uso legitimo
  /// (guardarse un token para mas tarde), y pegar solo por las dudas
  /// escribiria en la ventana equivocada.
  final bool pasteToActiveWindow;

  /// Auto-suscripcion al terminar. Solo tiene efecto en modo capturado
  /// (`showTerminalWindow = false`): cuando el comando termina bien, se
  /// interpreta `outputTail` como JSON, se saca el campo [autoSubscribeJsonField]
  /// (ej. `job_id`) y se arranca una suscripcion SignalR con ese valor como
  /// unico argumento del metodo invocado -- pensado para encadenar un
  /// `curl` que lanza un job con la suscripcion a su progreso, sin que el
  /// usuario tenga que copiar el id a mano. "Activada" = las cuatro
  /// columnas de abajo estan completas; ninguna tiene sentido sola.
  final String? autoSubscribeBaseUrl;
  final String? autoSubscribeHubPath;
  final String? autoSubscribeInvokeMethod;
  final String? autoSubscribeJsonField;
  final bool autoSubscribeAllowInvalidCert;
  final bool isFavorite;

  /// Categoria a la que pertenece la accion. `null` = sin categorizar.
  /// Borrar el grupo deja la accion sin grupo (`setNull`), no la borra.
  final String? groupId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ActionsTableData({
    required this.id,
    required this.name,
    this.description,
    required this.icon,
    required this.colorHex,
    required this.actionType,
    this.commandTemplate,
    required this.requiresAdmin,
    this.terminalType,
    required this.showTerminalWindow,
    required this.pasteToActiveWindow,
    this.autoSubscribeBaseUrl,
    this.autoSubscribeHubPath,
    this.autoSubscribeInvokeMethod,
    this.autoSubscribeJsonField,
    required this.autoSubscribeAllowInvalidCert,
    required this.isFavorite,
    this.groupId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['icon'] = Variable<String>(icon);
    map['color_hex'] = Variable<String>(colorHex);
    {
      map['action_type'] = Variable<String>(
        $ActionsTableTable.$converteractionType.toSql(actionType),
      );
    }
    if (!nullToAbsent || commandTemplate != null) {
      map['command_template'] = Variable<String>(commandTemplate);
    }
    map['requires_admin'] = Variable<bool>(requiresAdmin);
    if (!nullToAbsent || terminalType != null) {
      map['terminal_type'] = Variable<String>(
        $ActionsTableTable.$converterterminalTypen.toSql(terminalType),
      );
    }
    map['show_terminal_window'] = Variable<bool>(showTerminalWindow);
    map['paste_to_active_window'] = Variable<bool>(pasteToActiveWindow);
    if (!nullToAbsent || autoSubscribeBaseUrl != null) {
      map['auto_subscribe_base_url'] = Variable<String>(autoSubscribeBaseUrl);
    }
    if (!nullToAbsent || autoSubscribeHubPath != null) {
      map['auto_subscribe_hub_path'] = Variable<String>(autoSubscribeHubPath);
    }
    if (!nullToAbsent || autoSubscribeInvokeMethod != null) {
      map['auto_subscribe_invoke_method'] = Variable<String>(
        autoSubscribeInvokeMethod,
      );
    }
    if (!nullToAbsent || autoSubscribeJsonField != null) {
      map['auto_subscribe_json_field'] = Variable<String>(
        autoSubscribeJsonField,
      );
    }
    map['auto_subscribe_allow_invalid_cert'] = Variable<bool>(
      autoSubscribeAllowInvalidCert,
    );
    map['is_favorite'] = Variable<bool>(isFavorite);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ActionsTableCompanion toCompanion(bool nullToAbsent) {
    return ActionsTableCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      icon: Value(icon),
      colorHex: Value(colorHex),
      actionType: Value(actionType),
      commandTemplate: commandTemplate == null && nullToAbsent
          ? const Value.absent()
          : Value(commandTemplate),
      requiresAdmin: Value(requiresAdmin),
      terminalType: terminalType == null && nullToAbsent
          ? const Value.absent()
          : Value(terminalType),
      showTerminalWindow: Value(showTerminalWindow),
      pasteToActiveWindow: Value(pasteToActiveWindow),
      autoSubscribeBaseUrl: autoSubscribeBaseUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(autoSubscribeBaseUrl),
      autoSubscribeHubPath: autoSubscribeHubPath == null && nullToAbsent
          ? const Value.absent()
          : Value(autoSubscribeHubPath),
      autoSubscribeInvokeMethod:
          autoSubscribeInvokeMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(autoSubscribeInvokeMethod),
      autoSubscribeJsonField: autoSubscribeJsonField == null && nullToAbsent
          ? const Value.absent()
          : Value(autoSubscribeJsonField),
      autoSubscribeAllowInvalidCert: Value(autoSubscribeAllowInvalidCert),
      isFavorite: Value(isFavorite),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ActionsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      icon: serializer.fromJson<String>(json['icon']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      actionType: $ActionsTableTable.$converteractionType.fromJson(
        serializer.fromJson<String>(json['actionType']),
      ),
      commandTemplate: serializer.fromJson<String?>(json['commandTemplate']),
      requiresAdmin: serializer.fromJson<bool>(json['requiresAdmin']),
      terminalType: $ActionsTableTable.$converterterminalTypen.fromJson(
        serializer.fromJson<String?>(json['terminalType']),
      ),
      showTerminalWindow: serializer.fromJson<bool>(json['showTerminalWindow']),
      pasteToActiveWindow: serializer.fromJson<bool>(
        json['pasteToActiveWindow'],
      ),
      autoSubscribeBaseUrl: serializer.fromJson<String?>(
        json['autoSubscribeBaseUrl'],
      ),
      autoSubscribeHubPath: serializer.fromJson<String?>(
        json['autoSubscribeHubPath'],
      ),
      autoSubscribeInvokeMethod: serializer.fromJson<String?>(
        json['autoSubscribeInvokeMethod'],
      ),
      autoSubscribeJsonField: serializer.fromJson<String?>(
        json['autoSubscribeJsonField'],
      ),
      autoSubscribeAllowInvalidCert: serializer.fromJson<bool>(
        json['autoSubscribeAllowInvalidCert'],
      ),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'icon': serializer.toJson<String>(icon),
      'colorHex': serializer.toJson<String>(colorHex),
      'actionType': serializer.toJson<String>(
        $ActionsTableTable.$converteractionType.toJson(actionType),
      ),
      'commandTemplate': serializer.toJson<String?>(commandTemplate),
      'requiresAdmin': serializer.toJson<bool>(requiresAdmin),
      'terminalType': serializer.toJson<String?>(
        $ActionsTableTable.$converterterminalTypen.toJson(terminalType),
      ),
      'showTerminalWindow': serializer.toJson<bool>(showTerminalWindow),
      'pasteToActiveWindow': serializer.toJson<bool>(pasteToActiveWindow),
      'autoSubscribeBaseUrl': serializer.toJson<String?>(autoSubscribeBaseUrl),
      'autoSubscribeHubPath': serializer.toJson<String?>(autoSubscribeHubPath),
      'autoSubscribeInvokeMethod': serializer.toJson<String?>(
        autoSubscribeInvokeMethod,
      ),
      'autoSubscribeJsonField': serializer.toJson<String?>(
        autoSubscribeJsonField,
      ),
      'autoSubscribeAllowInvalidCert': serializer.toJson<bool>(
        autoSubscribeAllowInvalidCert,
      ),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'groupId': serializer.toJson<String?>(groupId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ActionsTableData copyWith({
    String? id,
    String? name,
    Value<String?> description = const Value.absent(),
    String? icon,
    String? colorHex,
    ActionType? actionType,
    Value<String?> commandTemplate = const Value.absent(),
    bool? requiresAdmin,
    Value<TerminalType?> terminalType = const Value.absent(),
    bool? showTerminalWindow,
    bool? pasteToActiveWindow,
    Value<String?> autoSubscribeBaseUrl = const Value.absent(),
    Value<String?> autoSubscribeHubPath = const Value.absent(),
    Value<String?> autoSubscribeInvokeMethod = const Value.absent(),
    Value<String?> autoSubscribeJsonField = const Value.absent(),
    bool? autoSubscribeAllowInvalidCert,
    bool? isFavorite,
    Value<String?> groupId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ActionsTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    icon: icon ?? this.icon,
    colorHex: colorHex ?? this.colorHex,
    actionType: actionType ?? this.actionType,
    commandTemplate: commandTemplate.present
        ? commandTemplate.value
        : this.commandTemplate,
    requiresAdmin: requiresAdmin ?? this.requiresAdmin,
    terminalType: terminalType.present ? terminalType.value : this.terminalType,
    showTerminalWindow: showTerminalWindow ?? this.showTerminalWindow,
    pasteToActiveWindow: pasteToActiveWindow ?? this.pasteToActiveWindow,
    autoSubscribeBaseUrl: autoSubscribeBaseUrl.present
        ? autoSubscribeBaseUrl.value
        : this.autoSubscribeBaseUrl,
    autoSubscribeHubPath: autoSubscribeHubPath.present
        ? autoSubscribeHubPath.value
        : this.autoSubscribeHubPath,
    autoSubscribeInvokeMethod: autoSubscribeInvokeMethod.present
        ? autoSubscribeInvokeMethod.value
        : this.autoSubscribeInvokeMethod,
    autoSubscribeJsonField: autoSubscribeJsonField.present
        ? autoSubscribeJsonField.value
        : this.autoSubscribeJsonField,
    autoSubscribeAllowInvalidCert:
        autoSubscribeAllowInvalidCert ?? this.autoSubscribeAllowInvalidCert,
    isFavorite: isFavorite ?? this.isFavorite,
    groupId: groupId.present ? groupId.value : this.groupId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ActionsTableData copyWithCompanion(ActionsTableCompanion data) {
    return ActionsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      icon: data.icon.present ? data.icon.value : this.icon,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      actionType: data.actionType.present
          ? data.actionType.value
          : this.actionType,
      commandTemplate: data.commandTemplate.present
          ? data.commandTemplate.value
          : this.commandTemplate,
      requiresAdmin: data.requiresAdmin.present
          ? data.requiresAdmin.value
          : this.requiresAdmin,
      terminalType: data.terminalType.present
          ? data.terminalType.value
          : this.terminalType,
      showTerminalWindow: data.showTerminalWindow.present
          ? data.showTerminalWindow.value
          : this.showTerminalWindow,
      pasteToActiveWindow: data.pasteToActiveWindow.present
          ? data.pasteToActiveWindow.value
          : this.pasteToActiveWindow,
      autoSubscribeBaseUrl: data.autoSubscribeBaseUrl.present
          ? data.autoSubscribeBaseUrl.value
          : this.autoSubscribeBaseUrl,
      autoSubscribeHubPath: data.autoSubscribeHubPath.present
          ? data.autoSubscribeHubPath.value
          : this.autoSubscribeHubPath,
      autoSubscribeInvokeMethod: data.autoSubscribeInvokeMethod.present
          ? data.autoSubscribeInvokeMethod.value
          : this.autoSubscribeInvokeMethod,
      autoSubscribeJsonField: data.autoSubscribeJsonField.present
          ? data.autoSubscribeJsonField.value
          : this.autoSubscribeJsonField,
      autoSubscribeAllowInvalidCert: data.autoSubscribeAllowInvalidCert.present
          ? data.autoSubscribeAllowInvalidCert.value
          : this.autoSubscribeAllowInvalidCert,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('icon: $icon, ')
          ..write('colorHex: $colorHex, ')
          ..write('actionType: $actionType, ')
          ..write('commandTemplate: $commandTemplate, ')
          ..write('requiresAdmin: $requiresAdmin, ')
          ..write('terminalType: $terminalType, ')
          ..write('showTerminalWindow: $showTerminalWindow, ')
          ..write('pasteToActiveWindow: $pasteToActiveWindow, ')
          ..write('autoSubscribeBaseUrl: $autoSubscribeBaseUrl, ')
          ..write('autoSubscribeHubPath: $autoSubscribeHubPath, ')
          ..write('autoSubscribeInvokeMethod: $autoSubscribeInvokeMethod, ')
          ..write('autoSubscribeJsonField: $autoSubscribeJsonField, ')
          ..write(
            'autoSubscribeAllowInvalidCert: $autoSubscribeAllowInvalidCert, ',
          )
          ..write('isFavorite: $isFavorite, ')
          ..write('groupId: $groupId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    icon,
    colorHex,
    actionType,
    commandTemplate,
    requiresAdmin,
    terminalType,
    showTerminalWindow,
    pasteToActiveWindow,
    autoSubscribeBaseUrl,
    autoSubscribeHubPath,
    autoSubscribeInvokeMethod,
    autoSubscribeJsonField,
    autoSubscribeAllowInvalidCert,
    isFavorite,
    groupId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.icon == this.icon &&
          other.colorHex == this.colorHex &&
          other.actionType == this.actionType &&
          other.commandTemplate == this.commandTemplate &&
          other.requiresAdmin == this.requiresAdmin &&
          other.terminalType == this.terminalType &&
          other.showTerminalWindow == this.showTerminalWindow &&
          other.pasteToActiveWindow == this.pasteToActiveWindow &&
          other.autoSubscribeBaseUrl == this.autoSubscribeBaseUrl &&
          other.autoSubscribeHubPath == this.autoSubscribeHubPath &&
          other.autoSubscribeInvokeMethod == this.autoSubscribeInvokeMethod &&
          other.autoSubscribeJsonField == this.autoSubscribeJsonField &&
          other.autoSubscribeAllowInvalidCert ==
              this.autoSubscribeAllowInvalidCert &&
          other.isFavorite == this.isFavorite &&
          other.groupId == this.groupId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ActionsTableCompanion extends UpdateCompanion<ActionsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> icon;
  final Value<String> colorHex;
  final Value<ActionType> actionType;
  final Value<String?> commandTemplate;
  final Value<bool> requiresAdmin;
  final Value<TerminalType?> terminalType;
  final Value<bool> showTerminalWindow;
  final Value<bool> pasteToActiveWindow;
  final Value<String?> autoSubscribeBaseUrl;
  final Value<String?> autoSubscribeHubPath;
  final Value<String?> autoSubscribeInvokeMethod;
  final Value<String?> autoSubscribeJsonField;
  final Value<bool> autoSubscribeAllowInvalidCert;
  final Value<bool> isFavorite;
  final Value<String?> groupId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ActionsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.icon = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.actionType = const Value.absent(),
    this.commandTemplate = const Value.absent(),
    this.requiresAdmin = const Value.absent(),
    this.terminalType = const Value.absent(),
    this.showTerminalWindow = const Value.absent(),
    this.pasteToActiveWindow = const Value.absent(),
    this.autoSubscribeBaseUrl = const Value.absent(),
    this.autoSubscribeHubPath = const Value.absent(),
    this.autoSubscribeInvokeMethod = const Value.absent(),
    this.autoSubscribeJsonField = const Value.absent(),
    this.autoSubscribeAllowInvalidCert = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.groupId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionsTableCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.icon = const Value.absent(),
    this.colorHex = const Value.absent(),
    required ActionType actionType,
    this.commandTemplate = const Value.absent(),
    this.requiresAdmin = const Value.absent(),
    this.terminalType = const Value.absent(),
    this.showTerminalWindow = const Value.absent(),
    this.pasteToActiveWindow = const Value.absent(),
    this.autoSubscribeBaseUrl = const Value.absent(),
    this.autoSubscribeHubPath = const Value.absent(),
    this.autoSubscribeInvokeMethod = const Value.absent(),
    this.autoSubscribeJsonField = const Value.absent(),
    this.autoSubscribeAllowInvalidCert = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.groupId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       actionType = Value(actionType);
  static Insertable<ActionsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? icon,
    Expression<String>? colorHex,
    Expression<String>? actionType,
    Expression<String>? commandTemplate,
    Expression<bool>? requiresAdmin,
    Expression<String>? terminalType,
    Expression<bool>? showTerminalWindow,
    Expression<bool>? pasteToActiveWindow,
    Expression<String>? autoSubscribeBaseUrl,
    Expression<String>? autoSubscribeHubPath,
    Expression<String>? autoSubscribeInvokeMethod,
    Expression<String>? autoSubscribeJsonField,
    Expression<bool>? autoSubscribeAllowInvalidCert,
    Expression<bool>? isFavorite,
    Expression<String>? groupId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      if (colorHex != null) 'color_hex': colorHex,
      if (actionType != null) 'action_type': actionType,
      if (commandTemplate != null) 'command_template': commandTemplate,
      if (requiresAdmin != null) 'requires_admin': requiresAdmin,
      if (terminalType != null) 'terminal_type': terminalType,
      if (showTerminalWindow != null)
        'show_terminal_window': showTerminalWindow,
      if (pasteToActiveWindow != null)
        'paste_to_active_window': pasteToActiveWindow,
      if (autoSubscribeBaseUrl != null)
        'auto_subscribe_base_url': autoSubscribeBaseUrl,
      if (autoSubscribeHubPath != null)
        'auto_subscribe_hub_path': autoSubscribeHubPath,
      if (autoSubscribeInvokeMethod != null)
        'auto_subscribe_invoke_method': autoSubscribeInvokeMethod,
      if (autoSubscribeJsonField != null)
        'auto_subscribe_json_field': autoSubscribeJsonField,
      if (autoSubscribeAllowInvalidCert != null)
        'auto_subscribe_allow_invalid_cert': autoSubscribeAllowInvalidCert,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (groupId != null) 'group_id': groupId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<String>? icon,
    Value<String>? colorHex,
    Value<ActionType>? actionType,
    Value<String?>? commandTemplate,
    Value<bool>? requiresAdmin,
    Value<TerminalType?>? terminalType,
    Value<bool>? showTerminalWindow,
    Value<bool>? pasteToActiveWindow,
    Value<String?>? autoSubscribeBaseUrl,
    Value<String?>? autoSubscribeHubPath,
    Value<String?>? autoSubscribeInvokeMethod,
    Value<String?>? autoSubscribeJsonField,
    Value<bool>? autoSubscribeAllowInvalidCert,
    Value<bool>? isFavorite,
    Value<String?>? groupId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ActionsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      actionType: actionType ?? this.actionType,
      commandTemplate: commandTemplate ?? this.commandTemplate,
      requiresAdmin: requiresAdmin ?? this.requiresAdmin,
      terminalType: terminalType ?? this.terminalType,
      showTerminalWindow: showTerminalWindow ?? this.showTerminalWindow,
      pasteToActiveWindow: pasteToActiveWindow ?? this.pasteToActiveWindow,
      autoSubscribeBaseUrl: autoSubscribeBaseUrl ?? this.autoSubscribeBaseUrl,
      autoSubscribeHubPath: autoSubscribeHubPath ?? this.autoSubscribeHubPath,
      autoSubscribeInvokeMethod:
          autoSubscribeInvokeMethod ?? this.autoSubscribeInvokeMethod,
      autoSubscribeJsonField:
          autoSubscribeJsonField ?? this.autoSubscribeJsonField,
      autoSubscribeAllowInvalidCert:
          autoSubscribeAllowInvalidCert ?? this.autoSubscribeAllowInvalidCert,
      isFavorite: isFavorite ?? this.isFavorite,
      groupId: groupId ?? this.groupId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (actionType.present) {
      map['action_type'] = Variable<String>(
        $ActionsTableTable.$converteractionType.toSql(actionType.value),
      );
    }
    if (commandTemplate.present) {
      map['command_template'] = Variable<String>(commandTemplate.value);
    }
    if (requiresAdmin.present) {
      map['requires_admin'] = Variable<bool>(requiresAdmin.value);
    }
    if (terminalType.present) {
      map['terminal_type'] = Variable<String>(
        $ActionsTableTable.$converterterminalTypen.toSql(terminalType.value),
      );
    }
    if (showTerminalWindow.present) {
      map['show_terminal_window'] = Variable<bool>(showTerminalWindow.value);
    }
    if (pasteToActiveWindow.present) {
      map['paste_to_active_window'] = Variable<bool>(pasteToActiveWindow.value);
    }
    if (autoSubscribeBaseUrl.present) {
      map['auto_subscribe_base_url'] = Variable<String>(
        autoSubscribeBaseUrl.value,
      );
    }
    if (autoSubscribeHubPath.present) {
      map['auto_subscribe_hub_path'] = Variable<String>(
        autoSubscribeHubPath.value,
      );
    }
    if (autoSubscribeInvokeMethod.present) {
      map['auto_subscribe_invoke_method'] = Variable<String>(
        autoSubscribeInvokeMethod.value,
      );
    }
    if (autoSubscribeJsonField.present) {
      map['auto_subscribe_json_field'] = Variable<String>(
        autoSubscribeJsonField.value,
      );
    }
    if (autoSubscribeAllowInvalidCert.present) {
      map['auto_subscribe_allow_invalid_cert'] = Variable<bool>(
        autoSubscribeAllowInvalidCert.value,
      );
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('icon: $icon, ')
          ..write('colorHex: $colorHex, ')
          ..write('actionType: $actionType, ')
          ..write('commandTemplate: $commandTemplate, ')
          ..write('requiresAdmin: $requiresAdmin, ')
          ..write('terminalType: $terminalType, ')
          ..write('showTerminalWindow: $showTerminalWindow, ')
          ..write('pasteToActiveWindow: $pasteToActiveWindow, ')
          ..write('autoSubscribeBaseUrl: $autoSubscribeBaseUrl, ')
          ..write('autoSubscribeHubPath: $autoSubscribeHubPath, ')
          ..write('autoSubscribeInvokeMethod: $autoSubscribeInvokeMethod, ')
          ..write('autoSubscribeJsonField: $autoSubscribeJsonField, ')
          ..write(
            'autoSubscribeAllowInvalidCert: $autoSubscribeAllowInvalidCert, ',
          )
          ..write('isFavorite: $isFavorite, ')
          ..write('groupId: $groupId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionParametersTable extends ActionParameters
    with TableInfo<$ActionParametersTable, ActionParameter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionParametersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _actionIdMeta = const VerificationMeta(
    'actionId',
  );
  @override
  late final GeneratedColumn<String> actionId = GeneratedColumn<String>(
    'action_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES actions_table (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ParamInputType, String>
  inputType = GeneratedColumn<String>(
    'input_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  ).withConverter<ParamInputType>($ActionParametersTable.$converterinputType);
  static const VerificationMeta _defaultValueMeta = const VerificationMeta(
    'defaultValue',
  );
  @override
  late final GeneratedColumn<String> defaultValue = GeneratedColumn<String>(
    'default_value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _optionsJsonMeta = const VerificationMeta(
    'optionsJson',
  );
  @override
  late final GeneratedColumn<String> optionsJson = GeneratedColumn<String>(
    'options_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    actionId,
    key,
    label,
    inputType,
    defaultValue,
    optionsJson,
    orderIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_parameters';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionParameter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actionIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('default_value')) {
      context.handle(
        _defaultValueMeta,
        defaultValue.isAcceptableOrUnknown(
          data['default_value']!,
          _defaultValueMeta,
        ),
      );
    }
    if (data.containsKey('options_json')) {
      context.handle(
        _optionsJsonMeta,
        optionsJson.isAcceptableOrUnknown(
          data['options_json']!,
          _optionsJsonMeta,
        ),
      );
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActionParameter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionParameter(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      inputType: $ActionParametersTable.$converterinputType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}input_type'],
        )!,
      ),
      defaultValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_value'],
      ),
      optionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}options_json'],
      ),
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
    );
  }

  @override
  $ActionParametersTable createAlias(String alias) {
    return $ActionParametersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ParamInputType, String, String>
  $converterinputType = const EnumNameConverter<ParamInputType>(
    ParamInputType.values,
  );
}

class ActionParameter extends DataClass implements Insertable<ActionParameter> {
  final String id;
  final String actionId;

  /// Nombre usado en el template: migration_name
  final String key;

  /// Texto mostrado al usuario: "Nombre de migracion"
  final String label;
  final ParamInputType inputType;
  final String? defaultValue;

  /// Solo si inputType = select. JSON: ["Opcion A", "Opcion B"]
  final String? optionsJson;
  final int orderIndex;
  const ActionParameter({
    required this.id,
    required this.actionId,
    required this.key,
    required this.label,
    required this.inputType,
    this.defaultValue,
    this.optionsJson,
    required this.orderIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['action_id'] = Variable<String>(actionId);
    map['key'] = Variable<String>(key);
    map['label'] = Variable<String>(label);
    {
      map['input_type'] = Variable<String>(
        $ActionParametersTable.$converterinputType.toSql(inputType),
      );
    }
    if (!nullToAbsent || defaultValue != null) {
      map['default_value'] = Variable<String>(defaultValue);
    }
    if (!nullToAbsent || optionsJson != null) {
      map['options_json'] = Variable<String>(optionsJson);
    }
    map['order_index'] = Variable<int>(orderIndex);
    return map;
  }

  ActionParametersCompanion toCompanion(bool nullToAbsent) {
    return ActionParametersCompanion(
      id: Value(id),
      actionId: Value(actionId),
      key: Value(key),
      label: Value(label),
      inputType: Value(inputType),
      defaultValue: defaultValue == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultValue),
      optionsJson: optionsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(optionsJson),
      orderIndex: Value(orderIndex),
    );
  }

  factory ActionParameter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionParameter(
      id: serializer.fromJson<String>(json['id']),
      actionId: serializer.fromJson<String>(json['actionId']),
      key: serializer.fromJson<String>(json['key']),
      label: serializer.fromJson<String>(json['label']),
      inputType: $ActionParametersTable.$converterinputType.fromJson(
        serializer.fromJson<String>(json['inputType']),
      ),
      defaultValue: serializer.fromJson<String?>(json['defaultValue']),
      optionsJson: serializer.fromJson<String?>(json['optionsJson']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'actionId': serializer.toJson<String>(actionId),
      'key': serializer.toJson<String>(key),
      'label': serializer.toJson<String>(label),
      'inputType': serializer.toJson<String>(
        $ActionParametersTable.$converterinputType.toJson(inputType),
      ),
      'defaultValue': serializer.toJson<String?>(defaultValue),
      'optionsJson': serializer.toJson<String?>(optionsJson),
      'orderIndex': serializer.toJson<int>(orderIndex),
    };
  }

  ActionParameter copyWith({
    String? id,
    String? actionId,
    String? key,
    String? label,
    ParamInputType? inputType,
    Value<String?> defaultValue = const Value.absent(),
    Value<String?> optionsJson = const Value.absent(),
    int? orderIndex,
  }) => ActionParameter(
    id: id ?? this.id,
    actionId: actionId ?? this.actionId,
    key: key ?? this.key,
    label: label ?? this.label,
    inputType: inputType ?? this.inputType,
    defaultValue: defaultValue.present ? defaultValue.value : this.defaultValue,
    optionsJson: optionsJson.present ? optionsJson.value : this.optionsJson,
    orderIndex: orderIndex ?? this.orderIndex,
  );
  ActionParameter copyWithCompanion(ActionParametersCompanion data) {
    return ActionParameter(
      id: data.id.present ? data.id.value : this.id,
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      key: data.key.present ? data.key.value : this.key,
      label: data.label.present ? data.label.value : this.label,
      inputType: data.inputType.present ? data.inputType.value : this.inputType,
      defaultValue: data.defaultValue.present
          ? data.defaultValue.value
          : this.defaultValue,
      optionsJson: data.optionsJson.present
          ? data.optionsJson.value
          : this.optionsJson,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionParameter(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('key: $key, ')
          ..write('label: $label, ')
          ..write('inputType: $inputType, ')
          ..write('defaultValue: $defaultValue, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    actionId,
    key,
    label,
    inputType,
    defaultValue,
    optionsJson,
    orderIndex,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionParameter &&
          other.id == this.id &&
          other.actionId == this.actionId &&
          other.key == this.key &&
          other.label == this.label &&
          other.inputType == this.inputType &&
          other.defaultValue == this.defaultValue &&
          other.optionsJson == this.optionsJson &&
          other.orderIndex == this.orderIndex);
}

class ActionParametersCompanion extends UpdateCompanion<ActionParameter> {
  final Value<String> id;
  final Value<String> actionId;
  final Value<String> key;
  final Value<String> label;
  final Value<ParamInputType> inputType;
  final Value<String?> defaultValue;
  final Value<String?> optionsJson;
  final Value<int> orderIndex;
  final Value<int> rowid;
  const ActionParametersCompanion({
    this.id = const Value.absent(),
    this.actionId = const Value.absent(),
    this.key = const Value.absent(),
    this.label = const Value.absent(),
    this.inputType = const Value.absent(),
    this.defaultValue = const Value.absent(),
    this.optionsJson = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionParametersCompanion.insert({
    this.id = const Value.absent(),
    required String actionId,
    required String key,
    required String label,
    this.inputType = const Value.absent(),
    this.defaultValue = const Value.absent(),
    this.optionsJson = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : actionId = Value(actionId),
       key = Value(key),
       label = Value(label);
  static Insertable<ActionParameter> custom({
    Expression<String>? id,
    Expression<String>? actionId,
    Expression<String>? key,
    Expression<String>? label,
    Expression<String>? inputType,
    Expression<String>? defaultValue,
    Expression<String>? optionsJson,
    Expression<int>? orderIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (actionId != null) 'action_id': actionId,
      if (key != null) 'key': key,
      if (label != null) 'label': label,
      if (inputType != null) 'input_type': inputType,
      if (defaultValue != null) 'default_value': defaultValue,
      if (optionsJson != null) 'options_json': optionsJson,
      if (orderIndex != null) 'order_index': orderIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionParametersCompanion copyWith({
    Value<String>? id,
    Value<String>? actionId,
    Value<String>? key,
    Value<String>? label,
    Value<ParamInputType>? inputType,
    Value<String?>? defaultValue,
    Value<String?>? optionsJson,
    Value<int>? orderIndex,
    Value<int>? rowid,
  }) {
    return ActionParametersCompanion(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      key: key ?? this.key,
      label: label ?? this.label,
      inputType: inputType ?? this.inputType,
      defaultValue: defaultValue ?? this.defaultValue,
      optionsJson: optionsJson ?? this.optionsJson,
      orderIndex: orderIndex ?? this.orderIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (inputType.present) {
      map['input_type'] = Variable<String>(
        $ActionParametersTable.$converterinputType.toSql(inputType.value),
      );
    }
    if (defaultValue.present) {
      map['default_value'] = Variable<String>(defaultValue.value);
    }
    if (optionsJson.present) {
      map['options_json'] = Variable<String>(optionsJson.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionParametersCompanion(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('key: $key, ')
          ..write('label: $label, ')
          ..write('inputType: $inputType, ')
          ..write('defaultValue: $defaultValue, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MacroStepsTable extends MacroSteps
    with TableInfo<$MacroStepsTable, MacroStep> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MacroStepsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _macroActionIdMeta = const VerificationMeta(
    'macroActionId',
  );
  @override
  late final GeneratedColumn<String> macroActionId = GeneratedColumn<String>(
    'macro_action_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES actions_table (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _stepActionIdMeta = const VerificationMeta(
    'stepActionId',
  );
  @override
  late final GeneratedColumn<String> stepActionId = GeneratedColumn<String>(
    'step_action_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES actions_table (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _delayMsAfterMeta = const VerificationMeta(
    'delayMsAfter',
  );
  @override
  late final GeneratedColumn<int> delayMsAfter = GeneratedColumn<int>(
    'delay_ms_after',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    macroActionId,
    stepActionId,
    orderIndex,
    delayMsAfter,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'macro_steps';
  @override
  VerificationContext validateIntegrity(
    Insertable<MacroStep> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('macro_action_id')) {
      context.handle(
        _macroActionIdMeta,
        macroActionId.isAcceptableOrUnknown(
          data['macro_action_id']!,
          _macroActionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_macroActionIdMeta);
    }
    if (data.containsKey('step_action_id')) {
      context.handle(
        _stepActionIdMeta,
        stepActionId.isAcceptableOrUnknown(
          data['step_action_id']!,
          _stepActionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_stepActionIdMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    if (data.containsKey('delay_ms_after')) {
      context.handle(
        _delayMsAfterMeta,
        delayMsAfter.isAcceptableOrUnknown(
          data['delay_ms_after']!,
          _delayMsAfterMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MacroStep map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MacroStep(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      macroActionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}macro_action_id'],
      )!,
      stepActionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}step_action_id'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
      delayMsAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delay_ms_after'],
      )!,
    );
  }

  @override
  $MacroStepsTable createAlias(String alias) {
    return $MacroStepsTable(attachedDatabase, alias);
  }
}

class MacroStep extends DataClass implements Insertable<MacroStep> {
  final String id;

  /// La accion "contenedora" (actionType = macro).
  ///
  /// `@ReferenceName` desambigua esta FK de `stepActionId` -- ambas
  /// apuntan a `ActionsTable`, y sin esto drift_dev no puede generar
  /// nombres distintos para las relaciones inversas.
  final String macroActionId;

  /// La accion que se ejecuta en este paso.
  final String stepActionId;
  final int orderIndex;
  final int delayMsAfter;
  const MacroStep({
    required this.id,
    required this.macroActionId,
    required this.stepActionId,
    required this.orderIndex,
    required this.delayMsAfter,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['macro_action_id'] = Variable<String>(macroActionId);
    map['step_action_id'] = Variable<String>(stepActionId);
    map['order_index'] = Variable<int>(orderIndex);
    map['delay_ms_after'] = Variable<int>(delayMsAfter);
    return map;
  }

  MacroStepsCompanion toCompanion(bool nullToAbsent) {
    return MacroStepsCompanion(
      id: Value(id),
      macroActionId: Value(macroActionId),
      stepActionId: Value(stepActionId),
      orderIndex: Value(orderIndex),
      delayMsAfter: Value(delayMsAfter),
    );
  }

  factory MacroStep.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MacroStep(
      id: serializer.fromJson<String>(json['id']),
      macroActionId: serializer.fromJson<String>(json['macroActionId']),
      stepActionId: serializer.fromJson<String>(json['stepActionId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      delayMsAfter: serializer.fromJson<int>(json['delayMsAfter']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'macroActionId': serializer.toJson<String>(macroActionId),
      'stepActionId': serializer.toJson<String>(stepActionId),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'delayMsAfter': serializer.toJson<int>(delayMsAfter),
    };
  }

  MacroStep copyWith({
    String? id,
    String? macroActionId,
    String? stepActionId,
    int? orderIndex,
    int? delayMsAfter,
  }) => MacroStep(
    id: id ?? this.id,
    macroActionId: macroActionId ?? this.macroActionId,
    stepActionId: stepActionId ?? this.stepActionId,
    orderIndex: orderIndex ?? this.orderIndex,
    delayMsAfter: delayMsAfter ?? this.delayMsAfter,
  );
  MacroStep copyWithCompanion(MacroStepsCompanion data) {
    return MacroStep(
      id: data.id.present ? data.id.value : this.id,
      macroActionId: data.macroActionId.present
          ? data.macroActionId.value
          : this.macroActionId,
      stepActionId: data.stepActionId.present
          ? data.stepActionId.value
          : this.stepActionId,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
      delayMsAfter: data.delayMsAfter.present
          ? data.delayMsAfter.value
          : this.delayMsAfter,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MacroStep(')
          ..write('id: $id, ')
          ..write('macroActionId: $macroActionId, ')
          ..write('stepActionId: $stepActionId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('delayMsAfter: $delayMsAfter')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, macroActionId, stepActionId, orderIndex, delayMsAfter);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MacroStep &&
          other.id == this.id &&
          other.macroActionId == this.macroActionId &&
          other.stepActionId == this.stepActionId &&
          other.orderIndex == this.orderIndex &&
          other.delayMsAfter == this.delayMsAfter);
}

class MacroStepsCompanion extends UpdateCompanion<MacroStep> {
  final Value<String> id;
  final Value<String> macroActionId;
  final Value<String> stepActionId;
  final Value<int> orderIndex;
  final Value<int> delayMsAfter;
  final Value<int> rowid;
  const MacroStepsCompanion({
    this.id = const Value.absent(),
    this.macroActionId = const Value.absent(),
    this.stepActionId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.delayMsAfter = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MacroStepsCompanion.insert({
    this.id = const Value.absent(),
    required String macroActionId,
    required String stepActionId,
    required int orderIndex,
    this.delayMsAfter = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : macroActionId = Value(macroActionId),
       stepActionId = Value(stepActionId),
       orderIndex = Value(orderIndex);
  static Insertable<MacroStep> custom({
    Expression<String>? id,
    Expression<String>? macroActionId,
    Expression<String>? stepActionId,
    Expression<int>? orderIndex,
    Expression<int>? delayMsAfter,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (macroActionId != null) 'macro_action_id': macroActionId,
      if (stepActionId != null) 'step_action_id': stepActionId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (delayMsAfter != null) 'delay_ms_after': delayMsAfter,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MacroStepsCompanion copyWith({
    Value<String>? id,
    Value<String>? macroActionId,
    Value<String>? stepActionId,
    Value<int>? orderIndex,
    Value<int>? delayMsAfter,
    Value<int>? rowid,
  }) {
    return MacroStepsCompanion(
      id: id ?? this.id,
      macroActionId: macroActionId ?? this.macroActionId,
      stepActionId: stepActionId ?? this.stepActionId,
      orderIndex: orderIndex ?? this.orderIndex,
      delayMsAfter: delayMsAfter ?? this.delayMsAfter,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (macroActionId.present) {
      map['macro_action_id'] = Variable<String>(macroActionId.value);
    }
    if (stepActionId.present) {
      map['step_action_id'] = Variable<String>(stepActionId.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (delayMsAfter.present) {
      map['delay_ms_after'] = Variable<int>(delayMsAfter.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MacroStepsCompanion(')
          ..write('id: $id, ')
          ..write('macroActionId: $macroActionId, ')
          ..write('stepActionId: $stepActionId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('delayMsAfter: $delayMsAfter, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('folder'),
  );
  static const VerificationMeta _colorHexMeta = const VerificationMeta(
    'colorHex',
  );
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
    'color_hex',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#22C55E'),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _autoDetectProcessMeta = const VerificationMeta(
    'autoDetectProcess',
  );
  @override
  late final GeneratedColumn<String> autoDetectProcess =
      GeneratedColumn<String>(
        'auto_detect_process',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    icon,
    colorHex,
    isDefault,
    autoDetectProcess,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<Profile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color_hex')) {
      context.handle(
        _colorHexMeta,
        colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('auto_detect_process')) {
      context.handle(
        _autoDetectProcessMeta,
        autoDetectProcess.isAcceptableOrUnknown(
          data['auto_detect_process']!,
          _autoDetectProcessMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      colorHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_hex'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      autoDetectProcess: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auto_detect_process'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  final String id;
  final String name;
  final String icon;
  final String colorHex;
  final bool isDefault;

  /// Nombre de proceso para auto-deteccion (ej. "obs64.exe"). `null` =
  /// solo activacion manual.
  final String? autoDetectProcess;
  final DateTime createdAt;
  const Profile({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.isDefault,
    this.autoDetectProcess,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['color_hex'] = Variable<String>(colorHex);
    map['is_default'] = Variable<bool>(isDefault);
    if (!nullToAbsent || autoDetectProcess != null) {
      map['auto_detect_process'] = Variable<String>(autoDetectProcess);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      colorHex: Value(colorHex),
      isDefault: Value(isDefault),
      autoDetectProcess: autoDetectProcess == null && nullToAbsent
          ? const Value.absent()
          : Value(autoDetectProcess),
      createdAt: Value(createdAt),
    );
  }

  factory Profile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      autoDetectProcess: serializer.fromJson<String?>(
        json['autoDetectProcess'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'colorHex': serializer.toJson<String>(colorHex),
      'isDefault': serializer.toJson<bool>(isDefault),
      'autoDetectProcess': serializer.toJson<String?>(autoDetectProcess),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Profile copyWith({
    String? id,
    String? name,
    String? icon,
    String? colorHex,
    bool? isDefault,
    Value<String?> autoDetectProcess = const Value.absent(),
    DateTime? createdAt,
  }) => Profile(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    colorHex: colorHex ?? this.colorHex,
    isDefault: isDefault ?? this.isDefault,
    autoDetectProcess: autoDetectProcess.present
        ? autoDetectProcess.value
        : this.autoDetectProcess,
    createdAt: createdAt ?? this.createdAt,
  );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      autoDetectProcess: data.autoDetectProcess.present
          ? data.autoDetectProcess.value
          : this.autoDetectProcess,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('colorHex: $colorHex, ')
          ..write('isDefault: $isDefault, ')
          ..write('autoDetectProcess: $autoDetectProcess, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    icon,
    colorHex,
    isDefault,
    autoDetectProcess,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.colorHex == this.colorHex &&
          other.isDefault == this.isDefault &&
          other.autoDetectProcess == this.autoDetectProcess &&
          other.createdAt == this.createdAt);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> icon;
  final Value<String> colorHex;
  final Value<bool> isDefault;
  final Value<String?> autoDetectProcess;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.autoDetectProcess = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.icon = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.autoDetectProcess = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Profile> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<String>? colorHex,
    Expression<bool>? isDefault,
    Expression<String>? autoDetectProcess,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (colorHex != null) 'color_hex': colorHex,
      if (isDefault != null) 'is_default': isDefault,
      if (autoDetectProcess != null) 'auto_detect_process': autoDetectProcess,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? icon,
    Value<String>? colorHex,
    Value<bool>? isDefault,
    Value<String?>? autoDetectProcess,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      isDefault: isDefault ?? this.isDefault,
      autoDetectProcess: autoDetectProcess ?? this.autoDetectProcess,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (autoDetectProcess.present) {
      map['auto_detect_process'] = Variable<String>(autoDetectProcess.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('colorHex: $colorHex, ')
          ..write('isDefault: $isDefault, ')
          ..write('autoDetectProcess: $autoDetectProcess, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfileActionsTable extends ProfileActions
    with TableInfo<$ProfileActionsTable, ProfileAction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfileActionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _actionIdMeta = const VerificationMeta(
    'actionId',
  );
  @override
  late final GeneratedColumn<String> actionId = GeneratedColumn<String>(
    'action_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES actions_table (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [profileId, actionId, orderIndex];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_actions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileAction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actionIdMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, actionId};
  @override
  ProfileAction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileAction(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
    );
  }

  @override
  $ProfileActionsTable createAlias(String alias) {
    return $ProfileActionsTable(attachedDatabase, alias);
  }
}

class ProfileAction extends DataClass implements Insertable<ProfileAction> {
  final String profileId;
  final String actionId;
  final int orderIndex;
  const ProfileAction({
    required this.profileId,
    required this.actionId,
    required this.orderIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['action_id'] = Variable<String>(actionId);
    map['order_index'] = Variable<int>(orderIndex);
    return map;
  }

  ProfileActionsCompanion toCompanion(bool nullToAbsent) {
    return ProfileActionsCompanion(
      profileId: Value(profileId),
      actionId: Value(actionId),
      orderIndex: Value(orderIndex),
    );
  }

  factory ProfileAction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileAction(
      profileId: serializer.fromJson<String>(json['profileId']),
      actionId: serializer.fromJson<String>(json['actionId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'actionId': serializer.toJson<String>(actionId),
      'orderIndex': serializer.toJson<int>(orderIndex),
    };
  }

  ProfileAction copyWith({
    String? profileId,
    String? actionId,
    int? orderIndex,
  }) => ProfileAction(
    profileId: profileId ?? this.profileId,
    actionId: actionId ?? this.actionId,
    orderIndex: orderIndex ?? this.orderIndex,
  );
  ProfileAction copyWithCompanion(ProfileActionsCompanion data) {
    return ProfileAction(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileAction(')
          ..write('profileId: $profileId, ')
          ..write('actionId: $actionId, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(profileId, actionId, orderIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileAction &&
          other.profileId == this.profileId &&
          other.actionId == this.actionId &&
          other.orderIndex == this.orderIndex);
}

class ProfileActionsCompanion extends UpdateCompanion<ProfileAction> {
  final Value<String> profileId;
  final Value<String> actionId;
  final Value<int> orderIndex;
  final Value<int> rowid;
  const ProfileActionsCompanion({
    this.profileId = const Value.absent(),
    this.actionId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfileActionsCompanion.insert({
    required String profileId,
    required String actionId,
    this.orderIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       actionId = Value(actionId);
  static Insertable<ProfileAction> custom({
    Expression<String>? profileId,
    Expression<String>? actionId,
    Expression<int>? orderIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (actionId != null) 'action_id': actionId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfileActionsCompanion copyWith({
    Value<String>? profileId,
    Value<String>? actionId,
    Value<int>? orderIndex,
    Value<int>? rowid,
  }) {
    return ProfileActionsCompanion(
      profileId: profileId ?? this.profileId,
      actionId: actionId ?? this.actionId,
      orderIndex: orderIndex ?? this.orderIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileActionsCompanion(')
          ..write('profileId: $profileId, ')
          ..write('actionId: $actionId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DevicesTable extends Devices with TableInfo<$DevicesTable, Device> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DevicePlatform, String> platform =
      GeneratedColumn<String>(
        'platform',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DevicePlatform>($DevicesTable.$converterplatform);
  static const VerificationMeta _certFingerprintMeta = const VerificationMeta(
    'certFingerprint',
  );
  @override
  late final GeneratedColumn<String> certFingerprint = GeneratedColumn<String>(
    'cert_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TransportType?, String>
  lastTransportUsed = GeneratedColumn<String>(
    'last_transport_used',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<TransportType?>($DevicesTable.$converterlastTransportUsedn);
  static const VerificationMeta _lastConnectedAtMeta = const VerificationMeta(
    'lastConnectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastConnectedAt =
      GeneratedColumn<DateTime>(
        'last_connected_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isAuthorizedMeta = const VerificationMeta(
    'isAuthorized',
  );
  @override
  late final GeneratedColumn<bool> isAuthorized = GeneratedColumn<bool>(
    'is_authorized',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_authorized" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pairedAt = GeneratedColumn<DateTime>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _manualHostMeta = const VerificationMeta(
    'manualHost',
  );
  @override
  late final GeneratedColumn<String> manualHost = GeneratedColumn<String>(
    'manual_host',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _manualPortMeta = const VerificationMeta(
    'manualPort',
  );
  @override
  late final GeneratedColumn<int> manualPort = GeneratedColumn<int>(
    'manual_port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relayHostMeta = const VerificationMeta(
    'relayHost',
  );
  @override
  late final GeneratedColumn<String> relayHost = GeneratedColumn<String>(
    'relay_host',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relayPortMeta = const VerificationMeta(
    'relayPort',
  );
  @override
  late final GeneratedColumn<int> relayPort = GeneratedColumn<int>(
    'relay_port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relayTokenHexMeta = const VerificationMeta(
    'relayTokenHex',
  );
  @override
  late final GeneratedColumn<String> relayTokenHex = GeneratedColumn<String>(
    'relay_token_hex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    platform,
    certFingerprint,
    lastTransportUsed,
    lastConnectedAt,
    isAuthorized,
    pairedAt,
    manualHost,
    manualPort,
    relayHost,
    relayPort,
    relayTokenHex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<Device> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('cert_fingerprint')) {
      context.handle(
        _certFingerprintMeta,
        certFingerprint.isAcceptableOrUnknown(
          data['cert_fingerprint']!,
          _certFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_certFingerprintMeta);
    }
    if (data.containsKey('last_connected_at')) {
      context.handle(
        _lastConnectedAtMeta,
        lastConnectedAt.isAcceptableOrUnknown(
          data['last_connected_at']!,
          _lastConnectedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_authorized')) {
      context.handle(
        _isAuthorizedMeta,
        isAuthorized.isAcceptableOrUnknown(
          data['is_authorized']!,
          _isAuthorizedMeta,
        ),
      );
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    }
    if (data.containsKey('manual_host')) {
      context.handle(
        _manualHostMeta,
        manualHost.isAcceptableOrUnknown(data['manual_host']!, _manualHostMeta),
      );
    }
    if (data.containsKey('manual_port')) {
      context.handle(
        _manualPortMeta,
        manualPort.isAcceptableOrUnknown(data['manual_port']!, _manualPortMeta),
      );
    }
    if (data.containsKey('relay_host')) {
      context.handle(
        _relayHostMeta,
        relayHost.isAcceptableOrUnknown(data['relay_host']!, _relayHostMeta),
      );
    }
    if (data.containsKey('relay_port')) {
      context.handle(
        _relayPortMeta,
        relayPort.isAcceptableOrUnknown(data['relay_port']!, _relayPortMeta),
      );
    }
    if (data.containsKey('relay_token_hex')) {
      context.handle(
        _relayTokenHexMeta,
        relayTokenHex.isAcceptableOrUnknown(
          data['relay_token_hex']!,
          _relayTokenHexMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Device map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Device(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      platform: $DevicesTable.$converterplatform.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}platform'],
        )!,
      ),
      certFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cert_fingerprint'],
      )!,
      lastTransportUsed: $DevicesTable.$converterlastTransportUsedn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}last_transport_used'],
        ),
      ),
      lastConnectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_connected_at'],
      ),
      isAuthorized: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_authorized'],
      )!,
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paired_at'],
      )!,
      manualHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manual_host'],
      ),
      manualPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}manual_port'],
      ),
      relayHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relay_host'],
      ),
      relayPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}relay_port'],
      ),
      relayTokenHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relay_token_hex'],
      ),
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<DevicePlatform, String, String> $converterplatform =
      const EnumNameConverter<DevicePlatform>(DevicePlatform.values);
  static JsonTypeConverter2<TransportType, String, String>
  $converterlastTransportUsed = const EnumNameConverter<TransportType>(
    TransportType.values,
  );
  static JsonTypeConverter2<TransportType?, String?, String?>
  $converterlastTransportUsedn = JsonTypeConverter2.asNullable(
    $converterlastTransportUsed,
  );
}

class Device extends DataClass implements Insertable<Device> {
  final String id;

  /// "Tablet de Juan" o modelo detectado.
  final String name;
  final DevicePlatform platform;

  /// Huella del certificado TLS fijado en el pairing (certificate pinning).
  final String certFingerprint;
  final TransportType? lastTransportUsed;
  final DateTime? lastConnectedAt;

  /// Revocable sin borrar el dispositivo -- conserva el historial.
  final bool isAuthorized;
  final DateTime pairedAt;

  /// Direccion fija escrita a mano por el usuario (IP o hostname), para
  /// alcanzar la PC cuando mDNS no puede: fuera de la LAN, tipicamente por
  /// una VPN mesh tipo Tailscale.
  ///
  /// Es STICKY a proposito -- no se pisa con la direccion de cada conexion
  /// exitosa. La IP de la LAN la da el DHCP y cambia; la que el usuario
  /// escribio es justamente la que no cambia, y sobrescribirla al volver a
  /// casa dejaria el camino de datos moviles roto sin ningun aviso.
  final String? manualHost;
  final int? manualPort;

  /// Oferta del tunel por relay que la PC manda en cada sesion
  /// (`ConnectionEvent.relayOfferReceived`) -- a diferencia de
  /// `manualHost`/`manualPort` (los escribe el usuario), esto lo escribe
  /// solo el manejador del evento. `null` mientras la PC nunca prendio el
  /// tunel, o si lo apago (llega `host` vacio y se limpian los tres).
  final String? relayHost;
  final int? relayPort;
  final String? relayTokenHex;
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.certFingerprint,
    this.lastTransportUsed,
    this.lastConnectedAt,
    required this.isAuthorized,
    required this.pairedAt,
    this.manualHost,
    this.manualPort,
    this.relayHost,
    this.relayPort,
    this.relayTokenHex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    {
      map['platform'] = Variable<String>(
        $DevicesTable.$converterplatform.toSql(platform),
      );
    }
    map['cert_fingerprint'] = Variable<String>(certFingerprint);
    if (!nullToAbsent || lastTransportUsed != null) {
      map['last_transport_used'] = Variable<String>(
        $DevicesTable.$converterlastTransportUsedn.toSql(lastTransportUsed),
      );
    }
    if (!nullToAbsent || lastConnectedAt != null) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt);
    }
    map['is_authorized'] = Variable<bool>(isAuthorized);
    map['paired_at'] = Variable<DateTime>(pairedAt);
    if (!nullToAbsent || manualHost != null) {
      map['manual_host'] = Variable<String>(manualHost);
    }
    if (!nullToAbsent || manualPort != null) {
      map['manual_port'] = Variable<int>(manualPort);
    }
    if (!nullToAbsent || relayHost != null) {
      map['relay_host'] = Variable<String>(relayHost);
    }
    if (!nullToAbsent || relayPort != null) {
      map['relay_port'] = Variable<int>(relayPort);
    }
    if (!nullToAbsent || relayTokenHex != null) {
      map['relay_token_hex'] = Variable<String>(relayTokenHex);
    }
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      id: Value(id),
      name: Value(name),
      platform: Value(platform),
      certFingerprint: Value(certFingerprint),
      lastTransportUsed: lastTransportUsed == null && nullToAbsent
          ? const Value.absent()
          : Value(lastTransportUsed),
      lastConnectedAt: lastConnectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConnectedAt),
      isAuthorized: Value(isAuthorized),
      pairedAt: Value(pairedAt),
      manualHost: manualHost == null && nullToAbsent
          ? const Value.absent()
          : Value(manualHost),
      manualPort: manualPort == null && nullToAbsent
          ? const Value.absent()
          : Value(manualPort),
      relayHost: relayHost == null && nullToAbsent
          ? const Value.absent()
          : Value(relayHost),
      relayPort: relayPort == null && nullToAbsent
          ? const Value.absent()
          : Value(relayPort),
      relayTokenHex: relayTokenHex == null && nullToAbsent
          ? const Value.absent()
          : Value(relayTokenHex),
    );
  }

  factory Device.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Device(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      platform: $DevicesTable.$converterplatform.fromJson(
        serializer.fromJson<String>(json['platform']),
      ),
      certFingerprint: serializer.fromJson<String>(json['certFingerprint']),
      lastTransportUsed: $DevicesTable.$converterlastTransportUsedn.fromJson(
        serializer.fromJson<String?>(json['lastTransportUsed']),
      ),
      lastConnectedAt: serializer.fromJson<DateTime?>(json['lastConnectedAt']),
      isAuthorized: serializer.fromJson<bool>(json['isAuthorized']),
      pairedAt: serializer.fromJson<DateTime>(json['pairedAt']),
      manualHost: serializer.fromJson<String?>(json['manualHost']),
      manualPort: serializer.fromJson<int?>(json['manualPort']),
      relayHost: serializer.fromJson<String?>(json['relayHost']),
      relayPort: serializer.fromJson<int?>(json['relayPort']),
      relayTokenHex: serializer.fromJson<String?>(json['relayTokenHex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'platform': serializer.toJson<String>(
        $DevicesTable.$converterplatform.toJson(platform),
      ),
      'certFingerprint': serializer.toJson<String>(certFingerprint),
      'lastTransportUsed': serializer.toJson<String?>(
        $DevicesTable.$converterlastTransportUsedn.toJson(lastTransportUsed),
      ),
      'lastConnectedAt': serializer.toJson<DateTime?>(lastConnectedAt),
      'isAuthorized': serializer.toJson<bool>(isAuthorized),
      'pairedAt': serializer.toJson<DateTime>(pairedAt),
      'manualHost': serializer.toJson<String?>(manualHost),
      'manualPort': serializer.toJson<int?>(manualPort),
      'relayHost': serializer.toJson<String?>(relayHost),
      'relayPort': serializer.toJson<int?>(relayPort),
      'relayTokenHex': serializer.toJson<String?>(relayTokenHex),
    };
  }

  Device copyWith({
    String? id,
    String? name,
    DevicePlatform? platform,
    String? certFingerprint,
    Value<TransportType?> lastTransportUsed = const Value.absent(),
    Value<DateTime?> lastConnectedAt = const Value.absent(),
    bool? isAuthorized,
    DateTime? pairedAt,
    Value<String?> manualHost = const Value.absent(),
    Value<int?> manualPort = const Value.absent(),
    Value<String?> relayHost = const Value.absent(),
    Value<int?> relayPort = const Value.absent(),
    Value<String?> relayTokenHex = const Value.absent(),
  }) => Device(
    id: id ?? this.id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    certFingerprint: certFingerprint ?? this.certFingerprint,
    lastTransportUsed: lastTransportUsed.present
        ? lastTransportUsed.value
        : this.lastTransportUsed,
    lastConnectedAt: lastConnectedAt.present
        ? lastConnectedAt.value
        : this.lastConnectedAt,
    isAuthorized: isAuthorized ?? this.isAuthorized,
    pairedAt: pairedAt ?? this.pairedAt,
    manualHost: manualHost.present ? manualHost.value : this.manualHost,
    manualPort: manualPort.present ? manualPort.value : this.manualPort,
    relayHost: relayHost.present ? relayHost.value : this.relayHost,
    relayPort: relayPort.present ? relayPort.value : this.relayPort,
    relayTokenHex: relayTokenHex.present
        ? relayTokenHex.value
        : this.relayTokenHex,
  );
  Device copyWithCompanion(DevicesCompanion data) {
    return Device(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      platform: data.platform.present ? data.platform.value : this.platform,
      certFingerprint: data.certFingerprint.present
          ? data.certFingerprint.value
          : this.certFingerprint,
      lastTransportUsed: data.lastTransportUsed.present
          ? data.lastTransportUsed.value
          : this.lastTransportUsed,
      lastConnectedAt: data.lastConnectedAt.present
          ? data.lastConnectedAt.value
          : this.lastConnectedAt,
      isAuthorized: data.isAuthorized.present
          ? data.isAuthorized.value
          : this.isAuthorized,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
      manualHost: data.manualHost.present
          ? data.manualHost.value
          : this.manualHost,
      manualPort: data.manualPort.present
          ? data.manualPort.value
          : this.manualPort,
      relayHost: data.relayHost.present ? data.relayHost.value : this.relayHost,
      relayPort: data.relayPort.present ? data.relayPort.value : this.relayPort,
      relayTokenHex: data.relayTokenHex.present
          ? data.relayTokenHex.value
          : this.relayTokenHex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Device(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('certFingerprint: $certFingerprint, ')
          ..write('lastTransportUsed: $lastTransportUsed, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('isAuthorized: $isAuthorized, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('manualHost: $manualHost, ')
          ..write('manualPort: $manualPort, ')
          ..write('relayHost: $relayHost, ')
          ..write('relayPort: $relayPort, ')
          ..write('relayTokenHex: $relayTokenHex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    platform,
    certFingerprint,
    lastTransportUsed,
    lastConnectedAt,
    isAuthorized,
    pairedAt,
    manualHost,
    manualPort,
    relayHost,
    relayPort,
    relayTokenHex,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Device &&
          other.id == this.id &&
          other.name == this.name &&
          other.platform == this.platform &&
          other.certFingerprint == this.certFingerprint &&
          other.lastTransportUsed == this.lastTransportUsed &&
          other.lastConnectedAt == this.lastConnectedAt &&
          other.isAuthorized == this.isAuthorized &&
          other.pairedAt == this.pairedAt &&
          other.manualHost == this.manualHost &&
          other.manualPort == this.manualPort &&
          other.relayHost == this.relayHost &&
          other.relayPort == this.relayPort &&
          other.relayTokenHex == this.relayTokenHex);
}

class DevicesCompanion extends UpdateCompanion<Device> {
  final Value<String> id;
  final Value<String> name;
  final Value<DevicePlatform> platform;
  final Value<String> certFingerprint;
  final Value<TransportType?> lastTransportUsed;
  final Value<DateTime?> lastConnectedAt;
  final Value<bool> isAuthorized;
  final Value<DateTime> pairedAt;
  final Value<String?> manualHost;
  final Value<int?> manualPort;
  final Value<String?> relayHost;
  final Value<int?> relayPort;
  final Value<String?> relayTokenHex;
  final Value<int> rowid;
  const DevicesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.platform = const Value.absent(),
    this.certFingerprint = const Value.absent(),
    this.lastTransportUsed = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.isAuthorized = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.manualHost = const Value.absent(),
    this.manualPort = const Value.absent(),
    this.relayHost = const Value.absent(),
    this.relayPort = const Value.absent(),
    this.relayTokenHex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required DevicePlatform platform,
    required String certFingerprint,
    this.lastTransportUsed = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.isAuthorized = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.manualHost = const Value.absent(),
    this.manualPort = const Value.absent(),
    this.relayHost = const Value.absent(),
    this.relayPort = const Value.absent(),
    this.relayTokenHex = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       platform = Value(platform),
       certFingerprint = Value(certFingerprint);
  static Insertable<Device> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? platform,
    Expression<String>? certFingerprint,
    Expression<String>? lastTransportUsed,
    Expression<DateTime>? lastConnectedAt,
    Expression<bool>? isAuthorized,
    Expression<DateTime>? pairedAt,
    Expression<String>? manualHost,
    Expression<int>? manualPort,
    Expression<String>? relayHost,
    Expression<int>? relayPort,
    Expression<String>? relayTokenHex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (platform != null) 'platform': platform,
      if (certFingerprint != null) 'cert_fingerprint': certFingerprint,
      if (lastTransportUsed != null) 'last_transport_used': lastTransportUsed,
      if (lastConnectedAt != null) 'last_connected_at': lastConnectedAt,
      if (isAuthorized != null) 'is_authorized': isAuthorized,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (manualHost != null) 'manual_host': manualHost,
      if (manualPort != null) 'manual_port': manualPort,
      if (relayHost != null) 'relay_host': relayHost,
      if (relayPort != null) 'relay_port': relayPort,
      if (relayTokenHex != null) 'relay_token_hex': relayTokenHex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DevicePlatform>? platform,
    Value<String>? certFingerprint,
    Value<TransportType?>? lastTransportUsed,
    Value<DateTime?>? lastConnectedAt,
    Value<bool>? isAuthorized,
    Value<DateTime>? pairedAt,
    Value<String?>? manualHost,
    Value<int?>? manualPort,
    Value<String?>? relayHost,
    Value<int?>? relayPort,
    Value<String?>? relayTokenHex,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      certFingerprint: certFingerprint ?? this.certFingerprint,
      lastTransportUsed: lastTransportUsed ?? this.lastTransportUsed,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      isAuthorized: isAuthorized ?? this.isAuthorized,
      pairedAt: pairedAt ?? this.pairedAt,
      manualHost: manualHost ?? this.manualHost,
      manualPort: manualPort ?? this.manualPort,
      relayHost: relayHost ?? this.relayHost,
      relayPort: relayPort ?? this.relayPort,
      relayTokenHex: relayTokenHex ?? this.relayTokenHex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(
        $DevicesTable.$converterplatform.toSql(platform.value),
      );
    }
    if (certFingerprint.present) {
      map['cert_fingerprint'] = Variable<String>(certFingerprint.value);
    }
    if (lastTransportUsed.present) {
      map['last_transport_used'] = Variable<String>(
        $DevicesTable.$converterlastTransportUsedn.toSql(
          lastTransportUsed.value,
        ),
      );
    }
    if (lastConnectedAt.present) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt.value);
    }
    if (isAuthorized.present) {
      map['is_authorized'] = Variable<bool>(isAuthorized.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<DateTime>(pairedAt.value);
    }
    if (manualHost.present) {
      map['manual_host'] = Variable<String>(manualHost.value);
    }
    if (manualPort.present) {
      map['manual_port'] = Variable<int>(manualPort.value);
    }
    if (relayHost.present) {
      map['relay_host'] = Variable<String>(relayHost.value);
    }
    if (relayPort.present) {
      map['relay_port'] = Variable<int>(relayPort.value);
    }
    if (relayTokenHex.present) {
      map['relay_token_hex'] = Variable<String>(relayTokenHex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('certFingerprint: $certFingerprint, ')
          ..write('lastTransportUsed: $lastTransportUsed, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('isAuthorized: $isAuthorized, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('manualHost: $manualHost, ')
          ..write('manualPort: $manualPort, ')
          ..write('relayHost: $relayHost, ')
          ..write('relayPort: $relayPort, ')
          ..write('relayTokenHex: $relayTokenHex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlertRulesTable extends AlertRules
    with TableInfo<$AlertRulesTable, AlertRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlertRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  @override
  late final GeneratedColumnWithTypeConverter<AlertMetric, String> metric =
      GeneratedColumn<String>(
        'metric',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AlertMetric>($AlertRulesTable.$convertermetric);
  @override
  late final GeneratedColumnWithTypeConverter<AlertOperator, String>
  operatorType = GeneratedColumn<String>(
    'operator_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<AlertOperator>($AlertRulesTable.$converteroperatorType);
  static const VerificationMeta _thresholdMeta = const VerificationMeta(
    'threshold',
  );
  @override
  late final GeneratedColumn<double> threshold = GeneratedColumn<double>(
    'threshold',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isEnabledMeta = const VerificationMeta(
    'isEnabled',
  );
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
    'is_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  late final GeneratedColumnWithTypeConverter<NotifyTarget, String>
  notifyTarget = GeneratedColumn<String>(
    'notify_target',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('both'),
  ).withConverter<NotifyTarget>($AlertRulesTable.$converternotifyTarget);
  static const VerificationMeta _cooldownSecondsMeta = const VerificationMeta(
    'cooldownSeconds',
  );
  @override
  late final GeneratedColumn<int> cooldownSeconds = GeneratedColumn<int>(
    'cooldown_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(60),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    metric,
    operatorType,
    threshold,
    isEnabled,
    notifyTarget,
    cooldownSeconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alert_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlertRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('threshold')) {
      context.handle(
        _thresholdMeta,
        threshold.isAcceptableOrUnknown(data['threshold']!, _thresholdMeta),
      );
    } else if (isInserting) {
      context.missing(_thresholdMeta);
    }
    if (data.containsKey('is_enabled')) {
      context.handle(
        _isEnabledMeta,
        isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta),
      );
    }
    if (data.containsKey('cooldown_seconds')) {
      context.handle(
        _cooldownSecondsMeta,
        cooldownSeconds.isAcceptableOrUnknown(
          data['cooldown_seconds']!,
          _cooldownSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlertRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlertRule(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      metric: $AlertRulesTable.$convertermetric.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}metric'],
        )!,
      ),
      operatorType: $AlertRulesTable.$converteroperatorType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}operator_type'],
        )!,
      ),
      threshold: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}threshold'],
      )!,
      isEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_enabled'],
      )!,
      notifyTarget: $AlertRulesTable.$converternotifyTarget.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}notify_target'],
        )!,
      ),
      cooldownSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cooldown_seconds'],
      )!,
    );
  }

  @override
  $AlertRulesTable createAlias(String alias) {
    return $AlertRulesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AlertMetric, String, String> $convertermetric =
      const EnumNameConverter<AlertMetric>(AlertMetric.values);
  static JsonTypeConverter2<AlertOperator, String, String>
  $converteroperatorType = const EnumNameConverter<AlertOperator>(
    AlertOperator.values,
  );
  static JsonTypeConverter2<NotifyTarget, String, String>
  $converternotifyTarget = const EnumNameConverter<NotifyTarget>(
    NotifyTarget.values,
  );
}

class AlertRule extends DataClass implements Insertable<AlertRule> {
  final String id;
  final AlertMetric metric;
  final AlertOperator operatorType;
  final double threshold;
  final bool isEnabled;
  final NotifyTarget notifyTarget;

  /// Evita spam de alertas.
  final int cooldownSeconds;
  const AlertRule({
    required this.id,
    required this.metric,
    required this.operatorType,
    required this.threshold,
    required this.isEnabled,
    required this.notifyTarget,
    required this.cooldownSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['metric'] = Variable<String>(
        $AlertRulesTable.$convertermetric.toSql(metric),
      );
    }
    {
      map['operator_type'] = Variable<String>(
        $AlertRulesTable.$converteroperatorType.toSql(operatorType),
      );
    }
    map['threshold'] = Variable<double>(threshold);
    map['is_enabled'] = Variable<bool>(isEnabled);
    {
      map['notify_target'] = Variable<String>(
        $AlertRulesTable.$converternotifyTarget.toSql(notifyTarget),
      );
    }
    map['cooldown_seconds'] = Variable<int>(cooldownSeconds);
    return map;
  }

  AlertRulesCompanion toCompanion(bool nullToAbsent) {
    return AlertRulesCompanion(
      id: Value(id),
      metric: Value(metric),
      operatorType: Value(operatorType),
      threshold: Value(threshold),
      isEnabled: Value(isEnabled),
      notifyTarget: Value(notifyTarget),
      cooldownSeconds: Value(cooldownSeconds),
    );
  }

  factory AlertRule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlertRule(
      id: serializer.fromJson<String>(json['id']),
      metric: $AlertRulesTable.$convertermetric.fromJson(
        serializer.fromJson<String>(json['metric']),
      ),
      operatorType: $AlertRulesTable.$converteroperatorType.fromJson(
        serializer.fromJson<String>(json['operatorType']),
      ),
      threshold: serializer.fromJson<double>(json['threshold']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      notifyTarget: $AlertRulesTable.$converternotifyTarget.fromJson(
        serializer.fromJson<String>(json['notifyTarget']),
      ),
      cooldownSeconds: serializer.fromJson<int>(json['cooldownSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'metric': serializer.toJson<String>(
        $AlertRulesTable.$convertermetric.toJson(metric),
      ),
      'operatorType': serializer.toJson<String>(
        $AlertRulesTable.$converteroperatorType.toJson(operatorType),
      ),
      'threshold': serializer.toJson<double>(threshold),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'notifyTarget': serializer.toJson<String>(
        $AlertRulesTable.$converternotifyTarget.toJson(notifyTarget),
      ),
      'cooldownSeconds': serializer.toJson<int>(cooldownSeconds),
    };
  }

  AlertRule copyWith({
    String? id,
    AlertMetric? metric,
    AlertOperator? operatorType,
    double? threshold,
    bool? isEnabled,
    NotifyTarget? notifyTarget,
    int? cooldownSeconds,
  }) => AlertRule(
    id: id ?? this.id,
    metric: metric ?? this.metric,
    operatorType: operatorType ?? this.operatorType,
    threshold: threshold ?? this.threshold,
    isEnabled: isEnabled ?? this.isEnabled,
    notifyTarget: notifyTarget ?? this.notifyTarget,
    cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
  );
  AlertRule copyWithCompanion(AlertRulesCompanion data) {
    return AlertRule(
      id: data.id.present ? data.id.value : this.id,
      metric: data.metric.present ? data.metric.value : this.metric,
      operatorType: data.operatorType.present
          ? data.operatorType.value
          : this.operatorType,
      threshold: data.threshold.present ? data.threshold.value : this.threshold,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      notifyTarget: data.notifyTarget.present
          ? data.notifyTarget.value
          : this.notifyTarget,
      cooldownSeconds: data.cooldownSeconds.present
          ? data.cooldownSeconds.value
          : this.cooldownSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlertRule(')
          ..write('id: $id, ')
          ..write('metric: $metric, ')
          ..write('operatorType: $operatorType, ')
          ..write('threshold: $threshold, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('notifyTarget: $notifyTarget, ')
          ..write('cooldownSeconds: $cooldownSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    metric,
    operatorType,
    threshold,
    isEnabled,
    notifyTarget,
    cooldownSeconds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlertRule &&
          other.id == this.id &&
          other.metric == this.metric &&
          other.operatorType == this.operatorType &&
          other.threshold == this.threshold &&
          other.isEnabled == this.isEnabled &&
          other.notifyTarget == this.notifyTarget &&
          other.cooldownSeconds == this.cooldownSeconds);
}

class AlertRulesCompanion extends UpdateCompanion<AlertRule> {
  final Value<String> id;
  final Value<AlertMetric> metric;
  final Value<AlertOperator> operatorType;
  final Value<double> threshold;
  final Value<bool> isEnabled;
  final Value<NotifyTarget> notifyTarget;
  final Value<int> cooldownSeconds;
  final Value<int> rowid;
  const AlertRulesCompanion({
    this.id = const Value.absent(),
    this.metric = const Value.absent(),
    this.operatorType = const Value.absent(),
    this.threshold = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.notifyTarget = const Value.absent(),
    this.cooldownSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlertRulesCompanion.insert({
    this.id = const Value.absent(),
    required AlertMetric metric,
    required AlertOperator operatorType,
    required double threshold,
    this.isEnabled = const Value.absent(),
    this.notifyTarget = const Value.absent(),
    this.cooldownSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : metric = Value(metric),
       operatorType = Value(operatorType),
       threshold = Value(threshold);
  static Insertable<AlertRule> custom({
    Expression<String>? id,
    Expression<String>? metric,
    Expression<String>? operatorType,
    Expression<double>? threshold,
    Expression<bool>? isEnabled,
    Expression<String>? notifyTarget,
    Expression<int>? cooldownSeconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (metric != null) 'metric': metric,
      if (operatorType != null) 'operator_type': operatorType,
      if (threshold != null) 'threshold': threshold,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (notifyTarget != null) 'notify_target': notifyTarget,
      if (cooldownSeconds != null) 'cooldown_seconds': cooldownSeconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlertRulesCompanion copyWith({
    Value<String>? id,
    Value<AlertMetric>? metric,
    Value<AlertOperator>? operatorType,
    Value<double>? threshold,
    Value<bool>? isEnabled,
    Value<NotifyTarget>? notifyTarget,
    Value<int>? cooldownSeconds,
    Value<int>? rowid,
  }) {
    return AlertRulesCompanion(
      id: id ?? this.id,
      metric: metric ?? this.metric,
      operatorType: operatorType ?? this.operatorType,
      threshold: threshold ?? this.threshold,
      isEnabled: isEnabled ?? this.isEnabled,
      notifyTarget: notifyTarget ?? this.notifyTarget,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (metric.present) {
      map['metric'] = Variable<String>(
        $AlertRulesTable.$convertermetric.toSql(metric.value),
      );
    }
    if (operatorType.present) {
      map['operator_type'] = Variable<String>(
        $AlertRulesTable.$converteroperatorType.toSql(operatorType.value),
      );
    }
    if (threshold.present) {
      map['threshold'] = Variable<double>(threshold.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (notifyTarget.present) {
      map['notify_target'] = Variable<String>(
        $AlertRulesTable.$converternotifyTarget.toSql(notifyTarget.value),
      );
    }
    if (cooldownSeconds.present) {
      map['cooldown_seconds'] = Variable<int>(cooldownSeconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlertRulesCompanion(')
          ..write('id: $id, ')
          ..write('metric: $metric, ')
          ..write('operatorType: $operatorType, ')
          ..write('threshold: $threshold, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('notifyTarget: $notifyTarget, ')
          ..write('cooldownSeconds: $cooldownSeconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HardwareHistoryTable extends HardwareHistory
    with TableInfo<$HardwareHistoryTable, HardwareHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HardwareHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _cpuUsageMeta = const VerificationMeta(
    'cpuUsage',
  );
  @override
  late final GeneratedColumn<double> cpuUsage = GeneratedColumn<double>(
    'cpu_usage',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cpuTempMeta = const VerificationMeta(
    'cpuTemp',
  );
  @override
  late final GeneratedColumn<double> cpuTemp = GeneratedColumn<double>(
    'cpu_temp',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cpuFreqMhzMeta = const VerificationMeta(
    'cpuFreqMhz',
  );
  @override
  late final GeneratedColumn<double> cpuFreqMhz = GeneratedColumn<double>(
    'cpu_freq_mhz',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gpuUsageMeta = const VerificationMeta(
    'gpuUsage',
  );
  @override
  late final GeneratedColumn<double> gpuUsage = GeneratedColumn<double>(
    'gpu_usage',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gpuTempMeta = const VerificationMeta(
    'gpuTemp',
  );
  @override
  late final GeneratedColumn<double> gpuTemp = GeneratedColumn<double>(
    'gpu_temp',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gpuVramUsedMbMeta = const VerificationMeta(
    'gpuVramUsedMb',
  );
  @override
  late final GeneratedColumn<double> gpuVramUsedMb = GeneratedColumn<double>(
    'gpu_vram_used_mb',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ramUsedMbMeta = const VerificationMeta(
    'ramUsedMb',
  );
  @override
  late final GeneratedColumn<double> ramUsedMb = GeneratedColumn<double>(
    'ram_used_mb',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ramTotalMbMeta = const VerificationMeta(
    'ramTotalMb',
  );
  @override
  late final GeneratedColumn<double> ramTotalMb = GeneratedColumn<double>(
    'ram_total_mb',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _diskReadBytesPerSecMeta =
      const VerificationMeta('diskReadBytesPerSec');
  @override
  late final GeneratedColumn<int> diskReadBytesPerSec = GeneratedColumn<int>(
    'disk_read_bytes_per_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _diskWriteBytesPerSecMeta =
      const VerificationMeta('diskWriteBytesPerSec');
  @override
  late final GeneratedColumn<int> diskWriteBytesPerSec = GeneratedColumn<int>(
    'disk_write_bytes_per_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _netRxBytesPerSecMeta = const VerificationMeta(
    'netRxBytesPerSec',
  );
  @override
  late final GeneratedColumn<int> netRxBytesPerSec = GeneratedColumn<int>(
    'net_rx_bytes_per_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _netTxBytesPerSecMeta = const VerificationMeta(
    'netTxBytesPerSec',
  );
  @override
  late final GeneratedColumn<int> netTxBytesPerSec = GeneratedColumn<int>(
    'net_tx_bytes_per_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    timestamp,
    cpuUsage,
    cpuTemp,
    cpuFreqMhz,
    gpuUsage,
    gpuTemp,
    gpuVramUsedMb,
    ramUsedMb,
    ramTotalMb,
    diskReadBytesPerSec,
    diskWriteBytesPerSec,
    netRxBytesPerSec,
    netTxBytesPerSec,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hardware_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<HardwareHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    if (data.containsKey('cpu_usage')) {
      context.handle(
        _cpuUsageMeta,
        cpuUsage.isAcceptableOrUnknown(data['cpu_usage']!, _cpuUsageMeta),
      );
    } else if (isInserting) {
      context.missing(_cpuUsageMeta);
    }
    if (data.containsKey('cpu_temp')) {
      context.handle(
        _cpuTempMeta,
        cpuTemp.isAcceptableOrUnknown(data['cpu_temp']!, _cpuTempMeta),
      );
    }
    if (data.containsKey('cpu_freq_mhz')) {
      context.handle(
        _cpuFreqMhzMeta,
        cpuFreqMhz.isAcceptableOrUnknown(
          data['cpu_freq_mhz']!,
          _cpuFreqMhzMeta,
        ),
      );
    }
    if (data.containsKey('gpu_usage')) {
      context.handle(
        _gpuUsageMeta,
        gpuUsage.isAcceptableOrUnknown(data['gpu_usage']!, _gpuUsageMeta),
      );
    }
    if (data.containsKey('gpu_temp')) {
      context.handle(
        _gpuTempMeta,
        gpuTemp.isAcceptableOrUnknown(data['gpu_temp']!, _gpuTempMeta),
      );
    }
    if (data.containsKey('gpu_vram_used_mb')) {
      context.handle(
        _gpuVramUsedMbMeta,
        gpuVramUsedMb.isAcceptableOrUnknown(
          data['gpu_vram_used_mb']!,
          _gpuVramUsedMbMeta,
        ),
      );
    }
    if (data.containsKey('ram_used_mb')) {
      context.handle(
        _ramUsedMbMeta,
        ramUsedMb.isAcceptableOrUnknown(data['ram_used_mb']!, _ramUsedMbMeta),
      );
    } else if (isInserting) {
      context.missing(_ramUsedMbMeta);
    }
    if (data.containsKey('ram_total_mb')) {
      context.handle(
        _ramTotalMbMeta,
        ramTotalMb.isAcceptableOrUnknown(
          data['ram_total_mb']!,
          _ramTotalMbMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ramTotalMbMeta);
    }
    if (data.containsKey('disk_read_bytes_per_sec')) {
      context.handle(
        _diskReadBytesPerSecMeta,
        diskReadBytesPerSec.isAcceptableOrUnknown(
          data['disk_read_bytes_per_sec']!,
          _diskReadBytesPerSecMeta,
        ),
      );
    }
    if (data.containsKey('disk_write_bytes_per_sec')) {
      context.handle(
        _diskWriteBytesPerSecMeta,
        diskWriteBytesPerSec.isAcceptableOrUnknown(
          data['disk_write_bytes_per_sec']!,
          _diskWriteBytesPerSecMeta,
        ),
      );
    }
    if (data.containsKey('net_rx_bytes_per_sec')) {
      context.handle(
        _netRxBytesPerSecMeta,
        netRxBytesPerSec.isAcceptableOrUnknown(
          data['net_rx_bytes_per_sec']!,
          _netRxBytesPerSecMeta,
        ),
      );
    }
    if (data.containsKey('net_tx_bytes_per_sec')) {
      context.handle(
        _netTxBytesPerSecMeta,
        netTxBytesPerSec.isAcceptableOrUnknown(
          data['net_tx_bytes_per_sec']!,
          _netTxBytesPerSecMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HardwareHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HardwareHistoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      cpuUsage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cpu_usage'],
      )!,
      cpuTemp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cpu_temp'],
      ),
      cpuFreqMhz: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cpu_freq_mhz'],
      ),
      gpuUsage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gpu_usage'],
      ),
      gpuTemp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gpu_temp'],
      ),
      gpuVramUsedMb: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gpu_vram_used_mb'],
      ),
      ramUsedMb: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ram_used_mb'],
      )!,
      ramTotalMb: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ram_total_mb'],
      )!,
      diskReadBytesPerSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disk_read_bytes_per_sec'],
      ),
      diskWriteBytesPerSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disk_write_bytes_per_sec'],
      ),
      netRxBytesPerSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}net_rx_bytes_per_sec'],
      ),
      netTxBytesPerSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}net_tx_bytes_per_sec'],
      ),
    );
  }

  @override
  $HardwareHistoryTable createAlias(String alias) {
    return $HardwareHistoryTable(attachedDatabase, alias);
  }
}

class HardwareHistoryData extends DataClass
    implements Insertable<HardwareHistoryData> {
  final int id;
  final DateTime timestamp;
  final double cpuUsage;
  final double? cpuTemp;
  final double? cpuFreqMhz;
  final double? gpuUsage;
  final double? gpuTemp;
  final double? gpuVramUsedMb;
  final double ramUsedMb;
  final double ramTotalMb;
  final int? diskReadBytesPerSec;
  final int? diskWriteBytesPerSec;

  /// Tasas de red del snapshot. Se agregaron en `schemaVersion 4`: la tabla
  /// original preveia E/S de disco (que `HardwareMonitor` todavia no
  /// produce, por eso las dos de arriba quedan siempre en `null`) pero no
  /// red, y la red es una de las 5 metricas que la UI grafica. Sin estas
  /// columnas el historial persistido habria mostrado 4 de 5.
  final int? netRxBytesPerSec;
  final int? netTxBytesPerSec;
  const HardwareHistoryData({
    required this.id,
    required this.timestamp,
    required this.cpuUsage,
    this.cpuTemp,
    this.cpuFreqMhz,
    this.gpuUsage,
    this.gpuTemp,
    this.gpuVramUsedMb,
    required this.ramUsedMb,
    required this.ramTotalMb,
    this.diskReadBytesPerSec,
    this.diskWriteBytesPerSec,
    this.netRxBytesPerSec,
    this.netTxBytesPerSec,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['cpu_usage'] = Variable<double>(cpuUsage);
    if (!nullToAbsent || cpuTemp != null) {
      map['cpu_temp'] = Variable<double>(cpuTemp);
    }
    if (!nullToAbsent || cpuFreqMhz != null) {
      map['cpu_freq_mhz'] = Variable<double>(cpuFreqMhz);
    }
    if (!nullToAbsent || gpuUsage != null) {
      map['gpu_usage'] = Variable<double>(gpuUsage);
    }
    if (!nullToAbsent || gpuTemp != null) {
      map['gpu_temp'] = Variable<double>(gpuTemp);
    }
    if (!nullToAbsent || gpuVramUsedMb != null) {
      map['gpu_vram_used_mb'] = Variable<double>(gpuVramUsedMb);
    }
    map['ram_used_mb'] = Variable<double>(ramUsedMb);
    map['ram_total_mb'] = Variable<double>(ramTotalMb);
    if (!nullToAbsent || diskReadBytesPerSec != null) {
      map['disk_read_bytes_per_sec'] = Variable<int>(diskReadBytesPerSec);
    }
    if (!nullToAbsent || diskWriteBytesPerSec != null) {
      map['disk_write_bytes_per_sec'] = Variable<int>(diskWriteBytesPerSec);
    }
    if (!nullToAbsent || netRxBytesPerSec != null) {
      map['net_rx_bytes_per_sec'] = Variable<int>(netRxBytesPerSec);
    }
    if (!nullToAbsent || netTxBytesPerSec != null) {
      map['net_tx_bytes_per_sec'] = Variable<int>(netTxBytesPerSec);
    }
    return map;
  }

  HardwareHistoryCompanion toCompanion(bool nullToAbsent) {
    return HardwareHistoryCompanion(
      id: Value(id),
      timestamp: Value(timestamp),
      cpuUsage: Value(cpuUsage),
      cpuTemp: cpuTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(cpuTemp),
      cpuFreqMhz: cpuFreqMhz == null && nullToAbsent
          ? const Value.absent()
          : Value(cpuFreqMhz),
      gpuUsage: gpuUsage == null && nullToAbsent
          ? const Value.absent()
          : Value(gpuUsage),
      gpuTemp: gpuTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(gpuTemp),
      gpuVramUsedMb: gpuVramUsedMb == null && nullToAbsent
          ? const Value.absent()
          : Value(gpuVramUsedMb),
      ramUsedMb: Value(ramUsedMb),
      ramTotalMb: Value(ramTotalMb),
      diskReadBytesPerSec: diskReadBytesPerSec == null && nullToAbsent
          ? const Value.absent()
          : Value(diskReadBytesPerSec),
      diskWriteBytesPerSec: diskWriteBytesPerSec == null && nullToAbsent
          ? const Value.absent()
          : Value(diskWriteBytesPerSec),
      netRxBytesPerSec: netRxBytesPerSec == null && nullToAbsent
          ? const Value.absent()
          : Value(netRxBytesPerSec),
      netTxBytesPerSec: netTxBytesPerSec == null && nullToAbsent
          ? const Value.absent()
          : Value(netTxBytesPerSec),
    );
  }

  factory HardwareHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HardwareHistoryData(
      id: serializer.fromJson<int>(json['id']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      cpuUsage: serializer.fromJson<double>(json['cpuUsage']),
      cpuTemp: serializer.fromJson<double?>(json['cpuTemp']),
      cpuFreqMhz: serializer.fromJson<double?>(json['cpuFreqMhz']),
      gpuUsage: serializer.fromJson<double?>(json['gpuUsage']),
      gpuTemp: serializer.fromJson<double?>(json['gpuTemp']),
      gpuVramUsedMb: serializer.fromJson<double?>(json['gpuVramUsedMb']),
      ramUsedMb: serializer.fromJson<double>(json['ramUsedMb']),
      ramTotalMb: serializer.fromJson<double>(json['ramTotalMb']),
      diskReadBytesPerSec: serializer.fromJson<int?>(
        json['diskReadBytesPerSec'],
      ),
      diskWriteBytesPerSec: serializer.fromJson<int?>(
        json['diskWriteBytesPerSec'],
      ),
      netRxBytesPerSec: serializer.fromJson<int?>(json['netRxBytesPerSec']),
      netTxBytesPerSec: serializer.fromJson<int?>(json['netTxBytesPerSec']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'cpuUsage': serializer.toJson<double>(cpuUsage),
      'cpuTemp': serializer.toJson<double?>(cpuTemp),
      'cpuFreqMhz': serializer.toJson<double?>(cpuFreqMhz),
      'gpuUsage': serializer.toJson<double?>(gpuUsage),
      'gpuTemp': serializer.toJson<double?>(gpuTemp),
      'gpuVramUsedMb': serializer.toJson<double?>(gpuVramUsedMb),
      'ramUsedMb': serializer.toJson<double>(ramUsedMb),
      'ramTotalMb': serializer.toJson<double>(ramTotalMb),
      'diskReadBytesPerSec': serializer.toJson<int?>(diskReadBytesPerSec),
      'diskWriteBytesPerSec': serializer.toJson<int?>(diskWriteBytesPerSec),
      'netRxBytesPerSec': serializer.toJson<int?>(netRxBytesPerSec),
      'netTxBytesPerSec': serializer.toJson<int?>(netTxBytesPerSec),
    };
  }

  HardwareHistoryData copyWith({
    int? id,
    DateTime? timestamp,
    double? cpuUsage,
    Value<double?> cpuTemp = const Value.absent(),
    Value<double?> cpuFreqMhz = const Value.absent(),
    Value<double?> gpuUsage = const Value.absent(),
    Value<double?> gpuTemp = const Value.absent(),
    Value<double?> gpuVramUsedMb = const Value.absent(),
    double? ramUsedMb,
    double? ramTotalMb,
    Value<int?> diskReadBytesPerSec = const Value.absent(),
    Value<int?> diskWriteBytesPerSec = const Value.absent(),
    Value<int?> netRxBytesPerSec = const Value.absent(),
    Value<int?> netTxBytesPerSec = const Value.absent(),
  }) => HardwareHistoryData(
    id: id ?? this.id,
    timestamp: timestamp ?? this.timestamp,
    cpuUsage: cpuUsage ?? this.cpuUsage,
    cpuTemp: cpuTemp.present ? cpuTemp.value : this.cpuTemp,
    cpuFreqMhz: cpuFreqMhz.present ? cpuFreqMhz.value : this.cpuFreqMhz,
    gpuUsage: gpuUsage.present ? gpuUsage.value : this.gpuUsage,
    gpuTemp: gpuTemp.present ? gpuTemp.value : this.gpuTemp,
    gpuVramUsedMb: gpuVramUsedMb.present
        ? gpuVramUsedMb.value
        : this.gpuVramUsedMb,
    ramUsedMb: ramUsedMb ?? this.ramUsedMb,
    ramTotalMb: ramTotalMb ?? this.ramTotalMb,
    diskReadBytesPerSec: diskReadBytesPerSec.present
        ? diskReadBytesPerSec.value
        : this.diskReadBytesPerSec,
    diskWriteBytesPerSec: diskWriteBytesPerSec.present
        ? diskWriteBytesPerSec.value
        : this.diskWriteBytesPerSec,
    netRxBytesPerSec: netRxBytesPerSec.present
        ? netRxBytesPerSec.value
        : this.netRxBytesPerSec,
    netTxBytesPerSec: netTxBytesPerSec.present
        ? netTxBytesPerSec.value
        : this.netTxBytesPerSec,
  );
  HardwareHistoryData copyWithCompanion(HardwareHistoryCompanion data) {
    return HardwareHistoryData(
      id: data.id.present ? data.id.value : this.id,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      cpuUsage: data.cpuUsage.present ? data.cpuUsage.value : this.cpuUsage,
      cpuTemp: data.cpuTemp.present ? data.cpuTemp.value : this.cpuTemp,
      cpuFreqMhz: data.cpuFreqMhz.present
          ? data.cpuFreqMhz.value
          : this.cpuFreqMhz,
      gpuUsage: data.gpuUsage.present ? data.gpuUsage.value : this.gpuUsage,
      gpuTemp: data.gpuTemp.present ? data.gpuTemp.value : this.gpuTemp,
      gpuVramUsedMb: data.gpuVramUsedMb.present
          ? data.gpuVramUsedMb.value
          : this.gpuVramUsedMb,
      ramUsedMb: data.ramUsedMb.present ? data.ramUsedMb.value : this.ramUsedMb,
      ramTotalMb: data.ramTotalMb.present
          ? data.ramTotalMb.value
          : this.ramTotalMb,
      diskReadBytesPerSec: data.diskReadBytesPerSec.present
          ? data.diskReadBytesPerSec.value
          : this.diskReadBytesPerSec,
      diskWriteBytesPerSec: data.diskWriteBytesPerSec.present
          ? data.diskWriteBytesPerSec.value
          : this.diskWriteBytesPerSec,
      netRxBytesPerSec: data.netRxBytesPerSec.present
          ? data.netRxBytesPerSec.value
          : this.netRxBytesPerSec,
      netTxBytesPerSec: data.netTxBytesPerSec.present
          ? data.netTxBytesPerSec.value
          : this.netTxBytesPerSec,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HardwareHistoryData(')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('cpuUsage: $cpuUsage, ')
          ..write('cpuTemp: $cpuTemp, ')
          ..write('cpuFreqMhz: $cpuFreqMhz, ')
          ..write('gpuUsage: $gpuUsage, ')
          ..write('gpuTemp: $gpuTemp, ')
          ..write('gpuVramUsedMb: $gpuVramUsedMb, ')
          ..write('ramUsedMb: $ramUsedMb, ')
          ..write('ramTotalMb: $ramTotalMb, ')
          ..write('diskReadBytesPerSec: $diskReadBytesPerSec, ')
          ..write('diskWriteBytesPerSec: $diskWriteBytesPerSec, ')
          ..write('netRxBytesPerSec: $netRxBytesPerSec, ')
          ..write('netTxBytesPerSec: $netTxBytesPerSec')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    timestamp,
    cpuUsage,
    cpuTemp,
    cpuFreqMhz,
    gpuUsage,
    gpuTemp,
    gpuVramUsedMb,
    ramUsedMb,
    ramTotalMb,
    diskReadBytesPerSec,
    diskWriteBytesPerSec,
    netRxBytesPerSec,
    netTxBytesPerSec,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HardwareHistoryData &&
          other.id == this.id &&
          other.timestamp == this.timestamp &&
          other.cpuUsage == this.cpuUsage &&
          other.cpuTemp == this.cpuTemp &&
          other.cpuFreqMhz == this.cpuFreqMhz &&
          other.gpuUsage == this.gpuUsage &&
          other.gpuTemp == this.gpuTemp &&
          other.gpuVramUsedMb == this.gpuVramUsedMb &&
          other.ramUsedMb == this.ramUsedMb &&
          other.ramTotalMb == this.ramTotalMb &&
          other.diskReadBytesPerSec == this.diskReadBytesPerSec &&
          other.diskWriteBytesPerSec == this.diskWriteBytesPerSec &&
          other.netRxBytesPerSec == this.netRxBytesPerSec &&
          other.netTxBytesPerSec == this.netTxBytesPerSec);
}

class HardwareHistoryCompanion extends UpdateCompanion<HardwareHistoryData> {
  final Value<int> id;
  final Value<DateTime> timestamp;
  final Value<double> cpuUsage;
  final Value<double?> cpuTemp;
  final Value<double?> cpuFreqMhz;
  final Value<double?> gpuUsage;
  final Value<double?> gpuTemp;
  final Value<double?> gpuVramUsedMb;
  final Value<double> ramUsedMb;
  final Value<double> ramTotalMb;
  final Value<int?> diskReadBytesPerSec;
  final Value<int?> diskWriteBytesPerSec;
  final Value<int?> netRxBytesPerSec;
  final Value<int?> netTxBytesPerSec;
  const HardwareHistoryCompanion({
    this.id = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.cpuUsage = const Value.absent(),
    this.cpuTemp = const Value.absent(),
    this.cpuFreqMhz = const Value.absent(),
    this.gpuUsage = const Value.absent(),
    this.gpuTemp = const Value.absent(),
    this.gpuVramUsedMb = const Value.absent(),
    this.ramUsedMb = const Value.absent(),
    this.ramTotalMb = const Value.absent(),
    this.diskReadBytesPerSec = const Value.absent(),
    this.diskWriteBytesPerSec = const Value.absent(),
    this.netRxBytesPerSec = const Value.absent(),
    this.netTxBytesPerSec = const Value.absent(),
  });
  HardwareHistoryCompanion.insert({
    this.id = const Value.absent(),
    this.timestamp = const Value.absent(),
    required double cpuUsage,
    this.cpuTemp = const Value.absent(),
    this.cpuFreqMhz = const Value.absent(),
    this.gpuUsage = const Value.absent(),
    this.gpuTemp = const Value.absent(),
    this.gpuVramUsedMb = const Value.absent(),
    required double ramUsedMb,
    required double ramTotalMb,
    this.diskReadBytesPerSec = const Value.absent(),
    this.diskWriteBytesPerSec = const Value.absent(),
    this.netRxBytesPerSec = const Value.absent(),
    this.netTxBytesPerSec = const Value.absent(),
  }) : cpuUsage = Value(cpuUsage),
       ramUsedMb = Value(ramUsedMb),
       ramTotalMb = Value(ramTotalMb);
  static Insertable<HardwareHistoryData> custom({
    Expression<int>? id,
    Expression<DateTime>? timestamp,
    Expression<double>? cpuUsage,
    Expression<double>? cpuTemp,
    Expression<double>? cpuFreqMhz,
    Expression<double>? gpuUsage,
    Expression<double>? gpuTemp,
    Expression<double>? gpuVramUsedMb,
    Expression<double>? ramUsedMb,
    Expression<double>? ramTotalMb,
    Expression<int>? diskReadBytesPerSec,
    Expression<int>? diskWriteBytesPerSec,
    Expression<int>? netRxBytesPerSec,
    Expression<int>? netTxBytesPerSec,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (timestamp != null) 'timestamp': timestamp,
      if (cpuUsage != null) 'cpu_usage': cpuUsage,
      if (cpuTemp != null) 'cpu_temp': cpuTemp,
      if (cpuFreqMhz != null) 'cpu_freq_mhz': cpuFreqMhz,
      if (gpuUsage != null) 'gpu_usage': gpuUsage,
      if (gpuTemp != null) 'gpu_temp': gpuTemp,
      if (gpuVramUsedMb != null) 'gpu_vram_used_mb': gpuVramUsedMb,
      if (ramUsedMb != null) 'ram_used_mb': ramUsedMb,
      if (ramTotalMb != null) 'ram_total_mb': ramTotalMb,
      if (diskReadBytesPerSec != null)
        'disk_read_bytes_per_sec': diskReadBytesPerSec,
      if (diskWriteBytesPerSec != null)
        'disk_write_bytes_per_sec': diskWriteBytesPerSec,
      if (netRxBytesPerSec != null) 'net_rx_bytes_per_sec': netRxBytesPerSec,
      if (netTxBytesPerSec != null) 'net_tx_bytes_per_sec': netTxBytesPerSec,
    });
  }

  HardwareHistoryCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? timestamp,
    Value<double>? cpuUsage,
    Value<double?>? cpuTemp,
    Value<double?>? cpuFreqMhz,
    Value<double?>? gpuUsage,
    Value<double?>? gpuTemp,
    Value<double?>? gpuVramUsedMb,
    Value<double>? ramUsedMb,
    Value<double>? ramTotalMb,
    Value<int?>? diskReadBytesPerSec,
    Value<int?>? diskWriteBytesPerSec,
    Value<int?>? netRxBytesPerSec,
    Value<int?>? netTxBytesPerSec,
  }) {
    return HardwareHistoryCompanion(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      cpuUsage: cpuUsage ?? this.cpuUsage,
      cpuTemp: cpuTemp ?? this.cpuTemp,
      cpuFreqMhz: cpuFreqMhz ?? this.cpuFreqMhz,
      gpuUsage: gpuUsage ?? this.gpuUsage,
      gpuTemp: gpuTemp ?? this.gpuTemp,
      gpuVramUsedMb: gpuVramUsedMb ?? this.gpuVramUsedMb,
      ramUsedMb: ramUsedMb ?? this.ramUsedMb,
      ramTotalMb: ramTotalMb ?? this.ramTotalMb,
      diskReadBytesPerSec: diskReadBytesPerSec ?? this.diskReadBytesPerSec,
      diskWriteBytesPerSec: diskWriteBytesPerSec ?? this.diskWriteBytesPerSec,
      netRxBytesPerSec: netRxBytesPerSec ?? this.netRxBytesPerSec,
      netTxBytesPerSec: netTxBytesPerSec ?? this.netTxBytesPerSec,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (cpuUsage.present) {
      map['cpu_usage'] = Variable<double>(cpuUsage.value);
    }
    if (cpuTemp.present) {
      map['cpu_temp'] = Variable<double>(cpuTemp.value);
    }
    if (cpuFreqMhz.present) {
      map['cpu_freq_mhz'] = Variable<double>(cpuFreqMhz.value);
    }
    if (gpuUsage.present) {
      map['gpu_usage'] = Variable<double>(gpuUsage.value);
    }
    if (gpuTemp.present) {
      map['gpu_temp'] = Variable<double>(gpuTemp.value);
    }
    if (gpuVramUsedMb.present) {
      map['gpu_vram_used_mb'] = Variable<double>(gpuVramUsedMb.value);
    }
    if (ramUsedMb.present) {
      map['ram_used_mb'] = Variable<double>(ramUsedMb.value);
    }
    if (ramTotalMb.present) {
      map['ram_total_mb'] = Variable<double>(ramTotalMb.value);
    }
    if (diskReadBytesPerSec.present) {
      map['disk_read_bytes_per_sec'] = Variable<int>(diskReadBytesPerSec.value);
    }
    if (diskWriteBytesPerSec.present) {
      map['disk_write_bytes_per_sec'] = Variable<int>(
        diskWriteBytesPerSec.value,
      );
    }
    if (netRxBytesPerSec.present) {
      map['net_rx_bytes_per_sec'] = Variable<int>(netRxBytesPerSec.value);
    }
    if (netTxBytesPerSec.present) {
      map['net_tx_bytes_per_sec'] = Variable<int>(netTxBytesPerSec.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HardwareHistoryCompanion(')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('cpuUsage: $cpuUsage, ')
          ..write('cpuTemp: $cpuTemp, ')
          ..write('cpuFreqMhz: $cpuFreqMhz, ')
          ..write('gpuUsage: $gpuUsage, ')
          ..write('gpuTemp: $gpuTemp, ')
          ..write('gpuVramUsedMb: $gpuVramUsedMb, ')
          ..write('ramUsedMb: $ramUsedMb, ')
          ..write('ramTotalMb: $ramTotalMb, ')
          ..write('diskReadBytesPerSec: $diskReadBytesPerSec, ')
          ..write('diskWriteBytesPerSec: $diskWriteBytesPerSec, ')
          ..write('netRxBytesPerSec: $netRxBytesPerSec, ')
          ..write('netTxBytesPerSec: $netTxBytesPerSec')
          ..write(')'))
        .toString();
  }
}

class $SecretsRefsTable extends SecretsRefs
    with TableInfo<$SecretsRefsTable, SecretsRef> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SecretsRefsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyNameMeta = const VerificationMeta(
    'keyName',
  );
  @override
  late final GeneratedColumn<String> keyName = GeneratedColumn<String>(
    'key_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  @override
  List<GeneratedColumn> get $columns => [keyName, description, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'secrets_refs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SecretsRef> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_name')) {
      context.handle(
        _keyNameMeta,
        keyName.isAcceptableOrUnknown(data['key_name']!, _keyNameMeta),
      );
    } else if (isInserting) {
      context.missing(_keyNameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyName};
  @override
  SecretsRef map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SecretsRef(
      keyName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SecretsRefsTable createAlias(String alias) {
    return $SecretsRefsTable(attachedDatabase, alias);
  }
}

class SecretsRef extends DataClass implements Insertable<SecretsRef> {
  /// Identificador usado en templates, ej. "API_TOKEN".
  final String keyName;
  final String? description;
  final DateTime createdAt;
  const SecretsRef({
    required this.keyName,
    this.description,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_name'] = Variable<String>(keyName);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SecretsRefsCompanion toCompanion(bool nullToAbsent) {
    return SecretsRefsCompanion(
      keyName: Value(keyName),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
    );
  }

  factory SecretsRef.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SecretsRef(
      keyName: serializer.fromJson<String>(json['keyName']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyName': serializer.toJson<String>(keyName),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SecretsRef copyWith({
    String? keyName,
    Value<String?> description = const Value.absent(),
    DateTime? createdAt,
  }) => SecretsRef(
    keyName: keyName ?? this.keyName,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
  );
  SecretsRef copyWithCompanion(SecretsRefsCompanion data) {
    return SecretsRef(
      keyName: data.keyName.present ? data.keyName.value : this.keyName,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SecretsRef(')
          ..write('keyName: $keyName, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(keyName, description, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SecretsRef &&
          other.keyName == this.keyName &&
          other.description == this.description &&
          other.createdAt == this.createdAt);
}

class SecretsRefsCompanion extends UpdateCompanion<SecretsRef> {
  final Value<String> keyName;
  final Value<String?> description;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SecretsRefsCompanion({
    this.keyName = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SecretsRefsCompanion.insert({
    required String keyName,
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : keyName = Value(keyName);
  static Insertable<SecretsRef> custom({
    Expression<String>? keyName,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyName != null) 'key_name': keyName,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SecretsRefsCompanion copyWith({
    Value<String>? keyName,
    Value<String?>? description,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SecretsRefsCompanion(
      keyName: keyName ?? this.keyName,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyName.present) {
      map['key_name'] = Variable<String>(keyName.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SecretsRefsCompanion(')
          ..write('keyName: $keyName, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WindowLayoutsTable extends WindowLayouts
    with TableInfo<$WindowLayoutsTable, WindowLayout> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WindowLayoutsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  @override
  late final GeneratedColumnWithTypeConverter<WindowMode, String> mode =
      GeneratedColumn<String>(
        'mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<WindowMode>($WindowLayoutsTable.$convertermode);
  static const VerificationMeta _posXMeta = const VerificationMeta('posX');
  @override
  late final GeneratedColumn<double> posX = GeneratedColumn<double>(
    'pos_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _posYMeta = const VerificationMeta('posY');
  @override
  late final GeneratedColumn<double> posY = GeneratedColumn<double>(
    'pos_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<double> width = GeneratedColumn<double>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<double> height = GeneratedColumn<double>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _monitorIdMeta = const VerificationMeta(
    'monitorId',
  );
  @override
  late final GeneratedColumn<String> monitorId = GeneratedColumn<String>(
    'monitor_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _alwaysOnTopMeta = const VerificationMeta(
    'alwaysOnTop',
  );
  @override
  late final GeneratedColumn<bool> alwaysOnTop = GeneratedColumn<bool>(
    'always_on_top',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("always_on_top" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mode,
    posX,
    posY,
    width,
    height,
    monitorId,
    alwaysOnTop,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'window_layouts';
  @override
  VerificationContext validateIntegrity(
    Insertable<WindowLayout> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('pos_x')) {
      context.handle(
        _posXMeta,
        posX.isAcceptableOrUnknown(data['pos_x']!, _posXMeta),
      );
    } else if (isInserting) {
      context.missing(_posXMeta);
    }
    if (data.containsKey('pos_y')) {
      context.handle(
        _posYMeta,
        posY.isAcceptableOrUnknown(data['pos_y']!, _posYMeta),
      );
    } else if (isInserting) {
      context.missing(_posYMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('monitor_id')) {
      context.handle(
        _monitorIdMeta,
        monitorId.isAcceptableOrUnknown(data['monitor_id']!, _monitorIdMeta),
      );
    }
    if (data.containsKey('always_on_top')) {
      context.handle(
        _alwaysOnTopMeta,
        alwaysOnTop.isAcceptableOrUnknown(
          data['always_on_top']!,
          _alwaysOnTopMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WindowLayout map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WindowLayout(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      mode: $WindowLayoutsTable.$convertermode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mode'],
        )!,
      ),
      posX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pos_x'],
      )!,
      posY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pos_y'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}height'],
      )!,
      monitorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}monitor_id'],
      ),
      alwaysOnTop: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}always_on_top'],
      )!,
    );
  }

  @override
  $WindowLayoutsTable createAlias(String alias) {
    return $WindowLayoutsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<WindowMode, String, String> $convertermode =
      const EnumNameConverter<WindowMode>(WindowMode.values);
}

class WindowLayout extends DataClass implements Insertable<WindowLayout> {
  final String id;
  final WindowMode mode;
  final double posX;
  final double posY;
  final double width;
  final double height;

  /// Identificador de monitor del SO.
  final String? monitorId;
  final bool alwaysOnTop;
  const WindowLayout({
    required this.id,
    required this.mode,
    required this.posX,
    required this.posY,
    required this.width,
    required this.height,
    this.monitorId,
    required this.alwaysOnTop,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['mode'] = Variable<String>(
        $WindowLayoutsTable.$convertermode.toSql(mode),
      );
    }
    map['pos_x'] = Variable<double>(posX);
    map['pos_y'] = Variable<double>(posY);
    map['width'] = Variable<double>(width);
    map['height'] = Variable<double>(height);
    if (!nullToAbsent || monitorId != null) {
      map['monitor_id'] = Variable<String>(monitorId);
    }
    map['always_on_top'] = Variable<bool>(alwaysOnTop);
    return map;
  }

  WindowLayoutsCompanion toCompanion(bool nullToAbsent) {
    return WindowLayoutsCompanion(
      id: Value(id),
      mode: Value(mode),
      posX: Value(posX),
      posY: Value(posY),
      width: Value(width),
      height: Value(height),
      monitorId: monitorId == null && nullToAbsent
          ? const Value.absent()
          : Value(monitorId),
      alwaysOnTop: Value(alwaysOnTop),
    );
  }

  factory WindowLayout.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WindowLayout(
      id: serializer.fromJson<String>(json['id']),
      mode: $WindowLayoutsTable.$convertermode.fromJson(
        serializer.fromJson<String>(json['mode']),
      ),
      posX: serializer.fromJson<double>(json['posX']),
      posY: serializer.fromJson<double>(json['posY']),
      width: serializer.fromJson<double>(json['width']),
      height: serializer.fromJson<double>(json['height']),
      monitorId: serializer.fromJson<String?>(json['monitorId']),
      alwaysOnTop: serializer.fromJson<bool>(json['alwaysOnTop']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mode': serializer.toJson<String>(
        $WindowLayoutsTable.$convertermode.toJson(mode),
      ),
      'posX': serializer.toJson<double>(posX),
      'posY': serializer.toJson<double>(posY),
      'width': serializer.toJson<double>(width),
      'height': serializer.toJson<double>(height),
      'monitorId': serializer.toJson<String?>(monitorId),
      'alwaysOnTop': serializer.toJson<bool>(alwaysOnTop),
    };
  }

  WindowLayout copyWith({
    String? id,
    WindowMode? mode,
    double? posX,
    double? posY,
    double? width,
    double? height,
    Value<String?> monitorId = const Value.absent(),
    bool? alwaysOnTop,
  }) => WindowLayout(
    id: id ?? this.id,
    mode: mode ?? this.mode,
    posX: posX ?? this.posX,
    posY: posY ?? this.posY,
    width: width ?? this.width,
    height: height ?? this.height,
    monitorId: monitorId.present ? monitorId.value : this.monitorId,
    alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
  );
  WindowLayout copyWithCompanion(WindowLayoutsCompanion data) {
    return WindowLayout(
      id: data.id.present ? data.id.value : this.id,
      mode: data.mode.present ? data.mode.value : this.mode,
      posX: data.posX.present ? data.posX.value : this.posX,
      posY: data.posY.present ? data.posY.value : this.posY,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      monitorId: data.monitorId.present ? data.monitorId.value : this.monitorId,
      alwaysOnTop: data.alwaysOnTop.present
          ? data.alwaysOnTop.value
          : this.alwaysOnTop,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WindowLayout(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('posX: $posX, ')
          ..write('posY: $posY, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('monitorId: $monitorId, ')
          ..write('alwaysOnTop: $alwaysOnTop')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, mode, posX, posY, width, height, monitorId, alwaysOnTop);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WindowLayout &&
          other.id == this.id &&
          other.mode == this.mode &&
          other.posX == this.posX &&
          other.posY == this.posY &&
          other.width == this.width &&
          other.height == this.height &&
          other.monitorId == this.monitorId &&
          other.alwaysOnTop == this.alwaysOnTop);
}

class WindowLayoutsCompanion extends UpdateCompanion<WindowLayout> {
  final Value<String> id;
  final Value<WindowMode> mode;
  final Value<double> posX;
  final Value<double> posY;
  final Value<double> width;
  final Value<double> height;
  final Value<String?> monitorId;
  final Value<bool> alwaysOnTop;
  final Value<int> rowid;
  const WindowLayoutsCompanion({
    this.id = const Value.absent(),
    this.mode = const Value.absent(),
    this.posX = const Value.absent(),
    this.posY = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.monitorId = const Value.absent(),
    this.alwaysOnTop = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WindowLayoutsCompanion.insert({
    this.id = const Value.absent(),
    required WindowMode mode,
    required double posX,
    required double posY,
    required double width,
    required double height,
    this.monitorId = const Value.absent(),
    this.alwaysOnTop = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mode = Value(mode),
       posX = Value(posX),
       posY = Value(posY),
       width = Value(width),
       height = Value(height);
  static Insertable<WindowLayout> custom({
    Expression<String>? id,
    Expression<String>? mode,
    Expression<double>? posX,
    Expression<double>? posY,
    Expression<double>? width,
    Expression<double>? height,
    Expression<String>? monitorId,
    Expression<bool>? alwaysOnTop,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mode != null) 'mode': mode,
      if (posX != null) 'pos_x': posX,
      if (posY != null) 'pos_y': posY,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (monitorId != null) 'monitor_id': monitorId,
      if (alwaysOnTop != null) 'always_on_top': alwaysOnTop,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WindowLayoutsCompanion copyWith({
    Value<String>? id,
    Value<WindowMode>? mode,
    Value<double>? posX,
    Value<double>? posY,
    Value<double>? width,
    Value<double>? height,
    Value<String?>? monitorId,
    Value<bool>? alwaysOnTop,
    Value<int>? rowid,
  }) {
    return WindowLayoutsCompanion(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      posX: posX ?? this.posX,
      posY: posY ?? this.posY,
      width: width ?? this.width,
      height: height ?? this.height,
      monitorId: monitorId ?? this.monitorId,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(
        $WindowLayoutsTable.$convertermode.toSql(mode.value),
      );
    }
    if (posX.present) {
      map['pos_x'] = Variable<double>(posX.value);
    }
    if (posY.present) {
      map['pos_y'] = Variable<double>(posY.value);
    }
    if (width.present) {
      map['width'] = Variable<double>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<double>(height.value);
    }
    if (monitorId.present) {
      map['monitor_id'] = Variable<String>(monitorId.value);
    }
    if (alwaysOnTop.present) {
      map['always_on_top'] = Variable<bool>(alwaysOnTop.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WindowLayoutsCompanion(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('posX: $posX, ')
          ..write('posY: $posY, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('monitorId: $monitorId, ')
          ..write('alwaysOnTop: $alwaysOnTop, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HubSubscriptionsTable extends HubSubscriptions
    with TableInfo<$HubSubscriptionsTable, HubSubscription> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HubSubscriptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 80,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<HubSubscriptionKind, String>
  kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<HubSubscriptionKind>($HubSubscriptionsTable.$converterkind);
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hubPathMeta = const VerificationMeta(
    'hubPath',
  );
  @override
  late final GeneratedColumn<String> hubPath = GeneratedColumn<String>(
    'hub_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _invokeMethodMeta = const VerificationMeta(
    'invokeMethod',
  );
  @override
  late final GeneratedColumn<String> invokeMethod = GeneratedColumn<String>(
    'invoke_method',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _invokeArgsJsonMeta = const VerificationMeta(
    'invokeArgsJson',
  );
  @override
  late final GeneratedColumn<String> invokeArgsJson = GeneratedColumn<String>(
    'invoke_args_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _allowInvalidCertMeta = const VerificationMeta(
    'allowInvalidCert',
  );
  @override
  late final GeneratedColumn<bool> allowInvalidCert = GeneratedColumn<bool>(
    'allow_invalid_cert',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_invalid_cert" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<HubSubscriptionStatus, String>
  status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('stopped'),
      ).withConverter<HubSubscriptionStatus>(
        $HubSubscriptionsTable.$converterstatus,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _lastEventAtMeta = const VerificationMeta(
    'lastEventAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastEventAt = GeneratedColumn<DateTime>(
    'last_event_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastEventSummaryMeta = const VerificationMeta(
    'lastEventSummary',
  );
  @override
  late final GeneratedColumn<String> lastEventSummary = GeneratedColumn<String>(
    'last_event_summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    kind,
    baseUrl,
    hubPath,
    invokeMethod,
    invokeArgsJson,
    allowInvalidCert,
    status,
    createdAt,
    lastEventAt,
    lastEventSummary,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hub_subscriptions';
  @override
  VerificationContext validateIntegrity(
    Insertable<HubSubscription> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('hub_path')) {
      context.handle(
        _hubPathMeta,
        hubPath.isAcceptableOrUnknown(data['hub_path']!, _hubPathMeta),
      );
    }
    if (data.containsKey('invoke_method')) {
      context.handle(
        _invokeMethodMeta,
        invokeMethod.isAcceptableOrUnknown(
          data['invoke_method']!,
          _invokeMethodMeta,
        ),
      );
    }
    if (data.containsKey('invoke_args_json')) {
      context.handle(
        _invokeArgsJsonMeta,
        invokeArgsJson.isAcceptableOrUnknown(
          data['invoke_args_json']!,
          _invokeArgsJsonMeta,
        ),
      );
    }
    if (data.containsKey('allow_invalid_cert')) {
      context.handle(
        _allowInvalidCertMeta,
        allowInvalidCert.isAcceptableOrUnknown(
          data['allow_invalid_cert']!,
          _allowInvalidCertMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_event_at')) {
      context.handle(
        _lastEventAtMeta,
        lastEventAt.isAcceptableOrUnknown(
          data['last_event_at']!,
          _lastEventAtMeta,
        ),
      );
    }
    if (data.containsKey('last_event_summary')) {
      context.handle(
        _lastEventSummaryMeta,
        lastEventSummary.isAcceptableOrUnknown(
          data['last_event_summary']!,
          _lastEventSummaryMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HubSubscription map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HubSubscription(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: $HubSubscriptionsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      hubPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hub_path'],
      ),
      invokeMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invoke_method'],
      ),
      invokeArgsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invoke_args_json'],
      ),
      allowInvalidCert: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_invalid_cert'],
      )!,
      status: $HubSubscriptionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastEventAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_event_at'],
      ),
      lastEventSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_event_summary'],
      ),
    );
  }

  @override
  $HubSubscriptionsTable createAlias(String alias) {
    return $HubSubscriptionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<HubSubscriptionKind, String, String>
  $converterkind = const EnumNameConverter<HubSubscriptionKind>(
    HubSubscriptionKind.values,
  );
  static JsonTypeConverter2<HubSubscriptionStatus, String, String>
  $converterstatus = const EnumNameConverter<HubSubscriptionStatus>(
    HubSubscriptionStatus.values,
  );
}

class HubSubscription extends DataClass implements Insertable<HubSubscription> {
  final String id;

  /// Etiqueta que pone el usuario (ej. "Entrenamiento IA -- tanda K").
  final String name;
  final HubSubscriptionKind kind;

  /// Origen `http(s)://host:puerto` si `kind = signalR`, o la URL
  /// `ws(s)://` completa si `kind = rawWebSocket`.
  final String baseUrl;

  /// Solo `signalR`: ej. `/hubs/plant-training-progress`.
  final String? hubPath;

  /// Solo `signalR`: metodo del hub a invocar apenas conecta, ej.
  /// `SubscribeToJob`.
  final String? invokeMethod;

  /// Solo `signalR`: JSON de la lista de argumentos (`["job-123"]`).
  final String? invokeArgsJson;

  /// Acepta un certificado TLS invalido (perfiles `https` de desarrollo con
  /// certificado autofirmado). Apagado por defecto -- prenderlo es una
  /// eleccion explicita del usuario, no un default silencioso.
  final bool allowInvalidCert;
  final HubSubscriptionStatus status;
  final DateTime createdAt;
  final DateTime? lastEventAt;

  /// Resumen corto del ultimo mensaje recibido (`eventName` + payload
  /// recortado) -- se actualiza junto con `lastEventAt` en `recordMessage`,
  /// nunca se limpia al desconectar/detener. Es lo que viaja en
  /// `HubSubscriptionSummary.lastEventSummary` hacia el panel remoto de
  /// Android sin tener que consultar el historial completo de mensajes.
  final String? lastEventSummary;
  const HubSubscription({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    this.hubPath,
    this.invokeMethod,
    this.invokeArgsJson,
    required this.allowInvalidCert,
    required this.status,
    required this.createdAt,
    this.lastEventAt,
    this.lastEventSummary,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    {
      map['kind'] = Variable<String>(
        $HubSubscriptionsTable.$converterkind.toSql(kind),
      );
    }
    map['base_url'] = Variable<String>(baseUrl);
    if (!nullToAbsent || hubPath != null) {
      map['hub_path'] = Variable<String>(hubPath);
    }
    if (!nullToAbsent || invokeMethod != null) {
      map['invoke_method'] = Variable<String>(invokeMethod);
    }
    if (!nullToAbsent || invokeArgsJson != null) {
      map['invoke_args_json'] = Variable<String>(invokeArgsJson);
    }
    map['allow_invalid_cert'] = Variable<bool>(allowInvalidCert);
    {
      map['status'] = Variable<String>(
        $HubSubscriptionsTable.$converterstatus.toSql(status),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastEventAt != null) {
      map['last_event_at'] = Variable<DateTime>(lastEventAt);
    }
    if (!nullToAbsent || lastEventSummary != null) {
      map['last_event_summary'] = Variable<String>(lastEventSummary);
    }
    return map;
  }

  HubSubscriptionsCompanion toCompanion(bool nullToAbsent) {
    return HubSubscriptionsCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      baseUrl: Value(baseUrl),
      hubPath: hubPath == null && nullToAbsent
          ? const Value.absent()
          : Value(hubPath),
      invokeMethod: invokeMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(invokeMethod),
      invokeArgsJson: invokeArgsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(invokeArgsJson),
      allowInvalidCert: Value(allowInvalidCert),
      status: Value(status),
      createdAt: Value(createdAt),
      lastEventAt: lastEventAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastEventAt),
      lastEventSummary: lastEventSummary == null && nullToAbsent
          ? const Value.absent()
          : Value(lastEventSummary),
    );
  }

  factory HubSubscription.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HubSubscription(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: $HubSubscriptionsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      hubPath: serializer.fromJson<String?>(json['hubPath']),
      invokeMethod: serializer.fromJson<String?>(json['invokeMethod']),
      invokeArgsJson: serializer.fromJson<String?>(json['invokeArgsJson']),
      allowInvalidCert: serializer.fromJson<bool>(json['allowInvalidCert']),
      status: $HubSubscriptionsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastEventAt: serializer.fromJson<DateTime?>(json['lastEventAt']),
      lastEventSummary: serializer.fromJson<String?>(json['lastEventSummary']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(
        $HubSubscriptionsTable.$converterkind.toJson(kind),
      ),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'hubPath': serializer.toJson<String?>(hubPath),
      'invokeMethod': serializer.toJson<String?>(invokeMethod),
      'invokeArgsJson': serializer.toJson<String?>(invokeArgsJson),
      'allowInvalidCert': serializer.toJson<bool>(allowInvalidCert),
      'status': serializer.toJson<String>(
        $HubSubscriptionsTable.$converterstatus.toJson(status),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastEventAt': serializer.toJson<DateTime?>(lastEventAt),
      'lastEventSummary': serializer.toJson<String?>(lastEventSummary),
    };
  }

  HubSubscription copyWith({
    String? id,
    String? name,
    HubSubscriptionKind? kind,
    String? baseUrl,
    Value<String?> hubPath = const Value.absent(),
    Value<String?> invokeMethod = const Value.absent(),
    Value<String?> invokeArgsJson = const Value.absent(),
    bool? allowInvalidCert,
    HubSubscriptionStatus? status,
    DateTime? createdAt,
    Value<DateTime?> lastEventAt = const Value.absent(),
    Value<String?> lastEventSummary = const Value.absent(),
  }) => HubSubscription(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    baseUrl: baseUrl ?? this.baseUrl,
    hubPath: hubPath.present ? hubPath.value : this.hubPath,
    invokeMethod: invokeMethod.present ? invokeMethod.value : this.invokeMethod,
    invokeArgsJson: invokeArgsJson.present
        ? invokeArgsJson.value
        : this.invokeArgsJson,
    allowInvalidCert: allowInvalidCert ?? this.allowInvalidCert,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    lastEventAt: lastEventAt.present ? lastEventAt.value : this.lastEventAt,
    lastEventSummary: lastEventSummary.present
        ? lastEventSummary.value
        : this.lastEventSummary,
  );
  HubSubscription copyWithCompanion(HubSubscriptionsCompanion data) {
    return HubSubscription(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      hubPath: data.hubPath.present ? data.hubPath.value : this.hubPath,
      invokeMethod: data.invokeMethod.present
          ? data.invokeMethod.value
          : this.invokeMethod,
      invokeArgsJson: data.invokeArgsJson.present
          ? data.invokeArgsJson.value
          : this.invokeArgsJson,
      allowInvalidCert: data.allowInvalidCert.present
          ? data.allowInvalidCert.value
          : this.allowInvalidCert,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastEventAt: data.lastEventAt.present
          ? data.lastEventAt.value
          : this.lastEventAt,
      lastEventSummary: data.lastEventSummary.present
          ? data.lastEventSummary.value
          : this.lastEventSummary,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HubSubscription(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('hubPath: $hubPath, ')
          ..write('invokeMethod: $invokeMethod, ')
          ..write('invokeArgsJson: $invokeArgsJson, ')
          ..write('allowInvalidCert: $allowInvalidCert, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastEventAt: $lastEventAt, ')
          ..write('lastEventSummary: $lastEventSummary')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    baseUrl,
    hubPath,
    invokeMethod,
    invokeArgsJson,
    allowInvalidCert,
    status,
    createdAt,
    lastEventAt,
    lastEventSummary,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HubSubscription &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.baseUrl == this.baseUrl &&
          other.hubPath == this.hubPath &&
          other.invokeMethod == this.invokeMethod &&
          other.invokeArgsJson == this.invokeArgsJson &&
          other.allowInvalidCert == this.allowInvalidCert &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.lastEventAt == this.lastEventAt &&
          other.lastEventSummary == this.lastEventSummary);
}

class HubSubscriptionsCompanion extends UpdateCompanion<HubSubscription> {
  final Value<String> id;
  final Value<String> name;
  final Value<HubSubscriptionKind> kind;
  final Value<String> baseUrl;
  final Value<String?> hubPath;
  final Value<String?> invokeMethod;
  final Value<String?> invokeArgsJson;
  final Value<bool> allowInvalidCert;
  final Value<HubSubscriptionStatus> status;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastEventAt;
  final Value<String?> lastEventSummary;
  final Value<int> rowid;
  const HubSubscriptionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.hubPath = const Value.absent(),
    this.invokeMethod = const Value.absent(),
    this.invokeArgsJson = const Value.absent(),
    this.allowInvalidCert = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastEventAt = const Value.absent(),
    this.lastEventSummary = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HubSubscriptionsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required HubSubscriptionKind kind,
    required String baseUrl,
    this.hubPath = const Value.absent(),
    this.invokeMethod = const Value.absent(),
    this.invokeArgsJson = const Value.absent(),
    this.allowInvalidCert = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastEventAt = const Value.absent(),
    this.lastEventSummary = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       kind = Value(kind),
       baseUrl = Value(baseUrl);
  static Insertable<HubSubscription> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? baseUrl,
    Expression<String>? hubPath,
    Expression<String>? invokeMethod,
    Expression<String>? invokeArgsJson,
    Expression<bool>? allowInvalidCert,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastEventAt,
    Expression<String>? lastEventSummary,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (baseUrl != null) 'base_url': baseUrl,
      if (hubPath != null) 'hub_path': hubPath,
      if (invokeMethod != null) 'invoke_method': invokeMethod,
      if (invokeArgsJson != null) 'invoke_args_json': invokeArgsJson,
      if (allowInvalidCert != null) 'allow_invalid_cert': allowInvalidCert,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (lastEventAt != null) 'last_event_at': lastEventAt,
      if (lastEventSummary != null) 'last_event_summary': lastEventSummary,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HubSubscriptionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<HubSubscriptionKind>? kind,
    Value<String>? baseUrl,
    Value<String?>? hubPath,
    Value<String?>? invokeMethod,
    Value<String?>? invokeArgsJson,
    Value<bool>? allowInvalidCert,
    Value<HubSubscriptionStatus>? status,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastEventAt,
    Value<String?>? lastEventSummary,
    Value<int>? rowid,
  }) {
    return HubSubscriptionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      baseUrl: baseUrl ?? this.baseUrl,
      hubPath: hubPath ?? this.hubPath,
      invokeMethod: invokeMethod ?? this.invokeMethod,
      invokeArgsJson: invokeArgsJson ?? this.invokeArgsJson,
      allowInvalidCert: allowInvalidCert ?? this.allowInvalidCert,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastEventAt: lastEventAt ?? this.lastEventAt,
      lastEventSummary: lastEventSummary ?? this.lastEventSummary,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $HubSubscriptionsTable.$converterkind.toSql(kind.value),
      );
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (hubPath.present) {
      map['hub_path'] = Variable<String>(hubPath.value);
    }
    if (invokeMethod.present) {
      map['invoke_method'] = Variable<String>(invokeMethod.value);
    }
    if (invokeArgsJson.present) {
      map['invoke_args_json'] = Variable<String>(invokeArgsJson.value);
    }
    if (allowInvalidCert.present) {
      map['allow_invalid_cert'] = Variable<bool>(allowInvalidCert.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $HubSubscriptionsTable.$converterstatus.toSql(status.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastEventAt.present) {
      map['last_event_at'] = Variable<DateTime>(lastEventAt.value);
    }
    if (lastEventSummary.present) {
      map['last_event_summary'] = Variable<String>(lastEventSummary.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HubSubscriptionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('hubPath: $hubPath, ')
          ..write('invokeMethod: $invokeMethod, ')
          ..write('invokeArgsJson: $invokeArgsJson, ')
          ..write('allowInvalidCert: $allowInvalidCert, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastEventAt: $lastEventAt, ')
          ..write('lastEventSummary: $lastEventSummary, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HubMessagesTable extends HubMessages
    with TableInfo<$HubMessagesTable, HubMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HubMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _subscriptionIdMeta = const VerificationMeta(
    'subscriptionId',
  );
  @override
  late final GeneratedColumn<String> subscriptionId = GeneratedColumn<String>(
    'subscription_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES hub_subscriptions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _eventNameMeta = const VerificationMeta(
    'eventName',
  );
  @override
  late final GeneratedColumn<String> eventName = GeneratedColumn<String>(
    'event_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subscriptionId,
    eventName,
    payloadJson,
    receivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hub_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<HubMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subscription_id')) {
      context.handle(
        _subscriptionIdMeta,
        subscriptionId.isAcceptableOrUnknown(
          data['subscription_id']!,
          _subscriptionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_subscriptionIdMeta);
    }
    if (data.containsKey('event_name')) {
      context.handle(
        _eventNameMeta,
        eventName.isAcceptableOrUnknown(data['event_name']!, _eventNameMeta),
      );
    } else if (isInserting) {
      context.missing(_eventNameMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HubMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HubMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      subscriptionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subscription_id'],
      )!,
      eventName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_name'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at'],
      )!,
    );
  }

  @override
  $HubMessagesTable createAlias(String alias) {
    return $HubMessagesTable(attachedDatabase, alias);
  }
}

class HubMessage extends DataClass implements Insertable<HubMessage> {
  final int id;
  final String subscriptionId;

  /// El `target` invocado (SignalR, ej. `ReceivePlantTrainingProgress`) o
  /// `"message"`/`"binary"` (WebSocket crudo).
  final String eventName;

  /// JSON tal cual vino del lado Rust -- siempre JSON valido, listo para
  /// mostrar formateado sin que la UI tenga que adivinar el formato.
  final String payloadJson;
  final DateTime receivedAt;
  const HubMessage({
    required this.id,
    required this.subscriptionId,
    required this.eventName,
    required this.payloadJson,
    required this.receivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subscription_id'] = Variable<String>(subscriptionId);
    map['event_name'] = Variable<String>(eventName);
    map['payload_json'] = Variable<String>(payloadJson);
    map['received_at'] = Variable<DateTime>(receivedAt);
    return map;
  }

  HubMessagesCompanion toCompanion(bool nullToAbsent) {
    return HubMessagesCompanion(
      id: Value(id),
      subscriptionId: Value(subscriptionId),
      eventName: Value(eventName),
      payloadJson: Value(payloadJson),
      receivedAt: Value(receivedAt),
    );
  }

  factory HubMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HubMessage(
      id: serializer.fromJson<int>(json['id']),
      subscriptionId: serializer.fromJson<String>(json['subscriptionId']),
      eventName: serializer.fromJson<String>(json['eventName']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subscriptionId': serializer.toJson<String>(subscriptionId),
      'eventName': serializer.toJson<String>(eventName),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
    };
  }

  HubMessage copyWith({
    int? id,
    String? subscriptionId,
    String? eventName,
    String? payloadJson,
    DateTime? receivedAt,
  }) => HubMessage(
    id: id ?? this.id,
    subscriptionId: subscriptionId ?? this.subscriptionId,
    eventName: eventName ?? this.eventName,
    payloadJson: payloadJson ?? this.payloadJson,
    receivedAt: receivedAt ?? this.receivedAt,
  );
  HubMessage copyWithCompanion(HubMessagesCompanion data) {
    return HubMessage(
      id: data.id.present ? data.id.value : this.id,
      subscriptionId: data.subscriptionId.present
          ? data.subscriptionId.value
          : this.subscriptionId,
      eventName: data.eventName.present ? data.eventName.value : this.eventName,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HubMessage(')
          ..write('id: $id, ')
          ..write('subscriptionId: $subscriptionId, ')
          ..write('eventName: $eventName, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, subscriptionId, eventName, payloadJson, receivedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HubMessage &&
          other.id == this.id &&
          other.subscriptionId == this.subscriptionId &&
          other.eventName == this.eventName &&
          other.payloadJson == this.payloadJson &&
          other.receivedAt == this.receivedAt);
}

class HubMessagesCompanion extends UpdateCompanion<HubMessage> {
  final Value<int> id;
  final Value<String> subscriptionId;
  final Value<String> eventName;
  final Value<String> payloadJson;
  final Value<DateTime> receivedAt;
  const HubMessagesCompanion({
    this.id = const Value.absent(),
    this.subscriptionId = const Value.absent(),
    this.eventName = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.receivedAt = const Value.absent(),
  });
  HubMessagesCompanion.insert({
    this.id = const Value.absent(),
    required String subscriptionId,
    required String eventName,
    required String payloadJson,
    this.receivedAt = const Value.absent(),
  }) : subscriptionId = Value(subscriptionId),
       eventName = Value(eventName),
       payloadJson = Value(payloadJson);
  static Insertable<HubMessage> custom({
    Expression<int>? id,
    Expression<String>? subscriptionId,
    Expression<String>? eventName,
    Expression<String>? payloadJson,
    Expression<DateTime>? receivedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subscriptionId != null) 'subscription_id': subscriptionId,
      if (eventName != null) 'event_name': eventName,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (receivedAt != null) 'received_at': receivedAt,
    });
  }

  HubMessagesCompanion copyWith({
    Value<int>? id,
    Value<String>? subscriptionId,
    Value<String>? eventName,
    Value<String>? payloadJson,
    Value<DateTime>? receivedAt,
  }) {
    return HubMessagesCompanion(
      id: id ?? this.id,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      eventName: eventName ?? this.eventName,
      payloadJson: payloadJson ?? this.payloadJson,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subscriptionId.present) {
      map['subscription_id'] = Variable<String>(subscriptionId.value);
    }
    if (eventName.present) {
      map['event_name'] = Variable<String>(eventName.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HubMessagesCompanion(')
          ..write('id: $id, ')
          ..write('subscriptionId: $subscriptionId, ')
          ..write('eventName: $eventName, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }
}

class $ChatConversationsTable extends ChatConversations
    with TableInfo<$ChatConversationsTable, ChatConversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _keepForeverMeta = const VerificationMeta(
    'keepForever',
  );
  @override
  late final GeneratedColumn<bool> keepForever = GeneratedColumn<bool>(
    'keep_forever',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("keep_forever" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    createdAt,
    updatedAt,
    keepForever,
    archivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatConversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('keep_forever')) {
      context.handle(
        _keepForeverMeta,
        keepForever.isAcceptableOrUnknown(
          data['keep_forever']!,
          _keepForeverMeta,
        ),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatConversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatConversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      keepForever: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}keep_forever'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
    );
  }

  @override
  $ChatConversationsTable createAlias(String alias) {
    return $ChatConversationsTable(attachedDatabase, alias);
  }
}

class ChatConversation extends DataClass
    implements Insertable<ChatConversation> {
  final String id;

  /// Sale de las primeras palabras del primer mensaje. Es lo unico que hace
  /// reconocible una charla en una lista de treinta.
  final String title;
  final DateTime createdAt;

  /// Cuando entro el ultimo mensaje. **Es lo que decide el archivado**, no
  /// `createdAt`: una conversacion que empezo hace tres meses pero que sigue
  /// viva hoy no tiene por que desaparecer.
  final DateTime updatedAt;

  /// El interruptor de "conservar para siempre". Con esto puesto, el
  /// archivado automatico la salta.
  final bool keepForever;

  /// Cuando se archivo. `null` es "activa". Archivar **no borra**: la
  /// conversacion sigue completa y se puede volver a abrir.
  final DateTime? archivedAt;
  const ChatConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.keepForever,
    this.archivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['keep_forever'] = Variable<bool>(keepForever);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    return map;
  }

  ChatConversationsCompanion toCompanion(bool nullToAbsent) {
    return ChatConversationsCompanion(
      id: Value(id),
      title: Value(title),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      keepForever: Value(keepForever),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
    );
  }

  factory ChatConversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatConversation(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      keepForever: serializer.fromJson<bool>(json['keepForever']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'keepForever': serializer.toJson<bool>(keepForever),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
    };
  }

  ChatConversation copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? keepForever,
    Value<DateTime?> archivedAt = const Value.absent(),
  }) => ChatConversation(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    keepForever: keepForever ?? this.keepForever,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
  );
  ChatConversation copyWithCompanion(ChatConversationsCompanion data) {
    return ChatConversation(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      keepForever: data.keepForever.present
          ? data.keepForever.value
          : this.keepForever,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatConversation(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('keepForever: $keepForever, ')
          ..write('archivedAt: $archivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, createdAt, updatedAt, keepForever, archivedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatConversation &&
          other.id == this.id &&
          other.title == this.title &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.keepForever == this.keepForever &&
          other.archivedAt == this.archivedAt);
}

class ChatConversationsCompanion extends UpdateCompanion<ChatConversation> {
  final Value<String> id;
  final Value<String> title;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> keepForever;
  final Value<DateTime?> archivedAt;
  final Value<int> rowid;
  const ChatConversationsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.keepForever = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatConversationsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.keepForever = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : title = Value(title);
  static Insertable<ChatConversation> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? keepForever,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (keepForever != null) 'keep_forever': keepForever,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatConversationsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? keepForever,
    Value<DateTime?>? archivedAt,
    Value<int>? rowid,
  }) {
    return ChatConversationsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      keepForever: keepForever ?? this.keepForever,
      archivedAt: archivedAt ?? this.archivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (keepForever.present) {
      map['keep_forever'] = Variable<bool>(keepForever.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatConversationsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('keepForever: $keepForever, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES chat_conversations (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ChatMessageKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ChatMessageKind>($ChatMessagesTable.$converterkind);
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ChatMessageOrigin, String>
  origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  ).withConverter<ChatMessageOrigin>($ChatMessagesTable.$converterorigin);
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    kind,
    content,
    origin,
    payload,
    position,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      kind: $ChatMessagesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      origin: $ChatMessagesTable.$converterorigin.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}origin'],
        )!,
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ChatMessageKind, String, String> $converterkind =
      const EnumNameConverter<ChatMessageKind>(ChatMessageKind.values);
  static JsonTypeConverter2<ChatMessageOrigin, String, String>
  $converterorigin = const EnumNameConverter<ChatMessageOrigin>(
    ChatMessageOrigin.values,
  );
}

class ChatMessage extends DataClass implements Insertable<ChatMessage> {
  final String id;
  final String conversationId;
  final ChatMessageKind kind;

  /// El texto que se muestra. En una herramienta es su resumen; en un
  /// borrador, su titulo.
  ///
  /// **No se puede llamar `text`**: ese es el nombre del constructor de
  /// columna de Drift (`text()`), y el getter lo taparia. drift_dev no genera
  /// nada para la tabla y el sintoma es que la tabla simplemente no existe,
  /// sin ningun error.
  final String content;
  final ChatMessageOrigin origin;

  /// Lo que no cabe en `text` y hace falta para volver a pintar la fila: el
  /// resultado de una herramienta, o el borrador entero en JSON.
  ///
  /// Se guarda como texto opaco a proposito. Darle columnas propias a cada
  /// tipo obligaria a migrar el esquema cada vez que cambie un borrador, que
  /// es justo lo que mas cambia.
  final String? payload;

  /// Orden dentro de la conversacion. **No se ordena por `createdAt`**: dos
  /// filas del mismo turno pueden compartir milisegundo y quedarian barajadas
  /// al releer, que en una charla se nota enseguida.
  final int position;
  final DateTime createdAt;
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.content,
    required this.origin,
    this.payload,
    required this.position,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    {
      map['kind'] = Variable<String>(
        $ChatMessagesTable.$converterkind.toSql(kind),
      );
    }
    map['content'] = Variable<String>(content);
    {
      map['origin'] = Variable<String>(
        $ChatMessagesTable.$converterorigin.toSql(origin),
      );
    }
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      kind: Value(kind),
      content: Value(content),
      origin: Value(origin),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      position: Value(position),
      createdAt: Value(createdAt),
    );
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessage(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      kind: $ChatMessagesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      content: serializer.fromJson<String>(json['content']),
      origin: $ChatMessagesTable.$converterorigin.fromJson(
        serializer.fromJson<String>(json['origin']),
      ),
      payload: serializer.fromJson<String?>(json['payload']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'kind': serializer.toJson<String>(
        $ChatMessagesTable.$converterkind.toJson(kind),
      ),
      'content': serializer.toJson<String>(content),
      'origin': serializer.toJson<String>(
        $ChatMessagesTable.$converterorigin.toJson(origin),
      ),
      'payload': serializer.toJson<String?>(payload),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    ChatMessageKind? kind,
    String? content,
    ChatMessageOrigin? origin,
    Value<String?> payload = const Value.absent(),
    int? position,
    DateTime? createdAt,
  }) => ChatMessage(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    kind: kind ?? this.kind,
    content: content ?? this.content,
    origin: origin ?? this.origin,
    payload: payload.present ? payload.value : this.payload,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
  );
  ChatMessage copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessage(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      kind: data.kind.present ? data.kind.value : this.kind,
      content: data.content.present ? data.content.value : this.content,
      origin: data.origin.present ? data.origin.value : this.origin,
      payload: data.payload.present ? data.payload.value : this.payload,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessage(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('kind: $kind, ')
          ..write('content: $content, ')
          ..write('origin: $origin, ')
          ..write('payload: $payload, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    kind,
    content,
    origin,
    payload,
    position,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.kind == this.kind &&
          other.content == this.content &&
          other.origin == this.origin &&
          other.payload == this.payload &&
          other.position == this.position &&
          other.createdAt == this.createdAt);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessage> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<ChatMessageKind> kind;
  final Value<String> content;
  final Value<ChatMessageOrigin> origin;
  final Value<String?> payload;
  final Value<int> position;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.kind = const Value.absent(),
    this.content = const Value.absent(),
    this.origin = const Value.absent(),
    this.payload = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    this.id = const Value.absent(),
    required String conversationId,
    required ChatMessageKind kind,
    required String content,
    this.origin = const Value.absent(),
    this.payload = const Value.absent(),
    required int position,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       kind = Value(kind),
       content = Value(content),
       position = Value(position);
  static Insertable<ChatMessage> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? kind,
    Expression<String>? content,
    Expression<String>? origin,
    Expression<String>? payload,
    Expression<int>? position,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (kind != null) 'kind': kind,
      if (content != null) 'content': content,
      if (origin != null) 'origin': origin,
      if (payload != null) 'payload': payload,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<ChatMessageKind>? kind,
    Value<String>? content,
    Value<ChatMessageOrigin>? origin,
    Value<String?>? payload,
    Value<int>? position,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      kind: kind ?? this.kind,
      content: content ?? this.content,
      origin: origin ?? this.origin,
      payload: payload ?? this.payload,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $ChatMessagesTable.$converterkind.toSql(kind.value),
      );
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(
        $ChatMessagesTable.$converterorigin.toSql(origin.value),
      );
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('kind: $kind, ')
          ..write('content: $content, ')
          ..write('origin: $origin, ')
          ..write('payload: $payload, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteMirrorTable extends NoteMirror
    with TableInfo<$NoteMirrorTable, NoteMirrorData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteMirrorTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseHashMeta = const VerificationMeta(
    'baseHash',
  );
  @override
  late final GeneratedColumn<String> baseHash = GeneratedColumn<String>(
    'base_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _localHashMeta = const VerificationMeta(
    'localHash',
  );
  @override
  late final GeneratedColumn<String> localHash = GeneratedColumn<String>(
    'local_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _privateMeta = const VerificationMeta(
    'private',
  );
  @override
  late final GeneratedColumn<bool> private = GeneratedColumn<bool>(
    'private',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("private" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _modifiedSecsMeta = const VerificationMeta(
    'modifiedSecs',
  );
  @override
  late final GeneratedColumn<int> modifiedSecs = GeneratedColumn<int>(
    'modified_secs',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _conflictContentMeta = const VerificationMeta(
    'conflictContent',
  );
  @override
  late final GeneratedColumn<String> conflictContent = GeneratedColumn<String>(
    'conflict_content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conflictHashMeta = const VerificationMeta(
    'conflictHash',
  );
  @override
  late final GeneratedColumn<String> conflictHash = GeneratedColumn<String>(
    'conflict_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    path,
    content,
    baseHash,
    localHash,
    private,
    modifiedSecs,
    updatedAt,
    conflictContent,
    conflictHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_mirror';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteMirrorData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('base_hash')) {
      context.handle(
        _baseHashMeta,
        baseHash.isAcceptableOrUnknown(data['base_hash']!, _baseHashMeta),
      );
    }
    if (data.containsKey('local_hash')) {
      context.handle(
        _localHashMeta,
        localHash.isAcceptableOrUnknown(data['local_hash']!, _localHashMeta),
      );
    }
    if (data.containsKey('private')) {
      context.handle(
        _privateMeta,
        private.isAcceptableOrUnknown(data['private']!, _privateMeta),
      );
    }
    if (data.containsKey('modified_secs')) {
      context.handle(
        _modifiedSecsMeta,
        modifiedSecs.isAcceptableOrUnknown(
          data['modified_secs']!,
          _modifiedSecsMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('conflict_content')) {
      context.handle(
        _conflictContentMeta,
        conflictContent.isAcceptableOrUnknown(
          data['conflict_content']!,
          _conflictContentMeta,
        ),
      );
    }
    if (data.containsKey('conflict_hash')) {
      context.handle(
        _conflictHashMeta,
        conflictHash.isAcceptableOrUnknown(
          data['conflict_hash']!,
          _conflictHashMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  NoteMirrorData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteMirrorData(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      baseHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_hash'],
      )!,
      localHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_hash'],
      )!,
      private: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}private'],
      )!,
      modifiedSecs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_secs'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      conflictContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_content'],
      ),
      conflictHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_hash'],
      ),
    );
  }

  @override
  $NoteMirrorTable createAlias(String alias) {
    return $NoteMirrorTable(attachedDatabase, alias);
  }
}

class NoteMirrorData extends DataClass implements Insertable<NoteMirrorData> {
  /// Relativa a la bóveda, con `/` y `.md`. Es la identidad de una nota en las
  /// dos puntas.
  final String path;

  /// El texto, con `\n`. La PC conserva el CRLF y el BOM del fichero al
  /// guardar, así que eso no viaja ni se guarda aquí.
  ///
  /// **No se puede llamar `text`**: ese es el nombre del constructor de columna
  /// de Drift y el getter lo taparía; drift_dev no generaría nada para la tabla
  /// y la tabla simplemente no existiría, sin ningún error (mismo gotcha que
  /// `chat_messages_table.dart`).
  final String content;

  /// El hash que tenía la nota en la PC cuando llegó. **Es la base de todo
  /// guardado posterior**: con él la PC decide si alguien la tocó mientras el
  /// teléfono estaba sin conexión.
  ///
  /// Vacío en una nota creada aquí que la PC todavía no conoce.
  final String baseHash;

  /// El hash de lo que hay ahora mismo en `content`. Si difiere de `baseHash`,
  /// hay algo escrito en el teléfono que la PC todavía no tiene.
  final String localHash;

  /// Está en `privado/`: ningún agente la lee.
  final bool private;

  /// Cuándo cambió en la PC, en segundos desde época (lo que da su sistema de
  /// ficheros). `null` si no lo dijo.
  final int? modifiedSecs;

  /// Cuándo se tocó aquí. Ordena la lista del móvil sin depender de la PC.
  final DateTime updatedAt;

  /// La versión de la PC cuando hubo un choque, guardada al lado en vez de
  /// pisar nada. `null` mientras no haya conflicto.
  ///
  /// Decisión del usuario: si la nota cambió en los dos sitios, **se conservan
  /// las dos** y elige él.
  final String? conflictContent;

  /// El hash de esa versión de la PC. Es el que hay que mandar como base si el
  /// usuario decide quedarse con lo del teléfono.
  final String? conflictHash;
  const NoteMirrorData({
    required this.path,
    required this.content,
    required this.baseHash,
    required this.localHash,
    required this.private,
    this.modifiedSecs,
    required this.updatedAt,
    this.conflictContent,
    this.conflictHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['content'] = Variable<String>(content);
    map['base_hash'] = Variable<String>(baseHash);
    map['local_hash'] = Variable<String>(localHash);
    map['private'] = Variable<bool>(private);
    if (!nullToAbsent || modifiedSecs != null) {
      map['modified_secs'] = Variable<int>(modifiedSecs);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || conflictContent != null) {
      map['conflict_content'] = Variable<String>(conflictContent);
    }
    if (!nullToAbsent || conflictHash != null) {
      map['conflict_hash'] = Variable<String>(conflictHash);
    }
    return map;
  }

  NoteMirrorCompanion toCompanion(bool nullToAbsent) {
    return NoteMirrorCompanion(
      path: Value(path),
      content: Value(content),
      baseHash: Value(baseHash),
      localHash: Value(localHash),
      private: Value(private),
      modifiedSecs: modifiedSecs == null && nullToAbsent
          ? const Value.absent()
          : Value(modifiedSecs),
      updatedAt: Value(updatedAt),
      conflictContent: conflictContent == null && nullToAbsent
          ? const Value.absent()
          : Value(conflictContent),
      conflictHash: conflictHash == null && nullToAbsent
          ? const Value.absent()
          : Value(conflictHash),
    );
  }

  factory NoteMirrorData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteMirrorData(
      path: serializer.fromJson<String>(json['path']),
      content: serializer.fromJson<String>(json['content']),
      baseHash: serializer.fromJson<String>(json['baseHash']),
      localHash: serializer.fromJson<String>(json['localHash']),
      private: serializer.fromJson<bool>(json['private']),
      modifiedSecs: serializer.fromJson<int?>(json['modifiedSecs']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      conflictContent: serializer.fromJson<String?>(json['conflictContent']),
      conflictHash: serializer.fromJson<String?>(json['conflictHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'content': serializer.toJson<String>(content),
      'baseHash': serializer.toJson<String>(baseHash),
      'localHash': serializer.toJson<String>(localHash),
      'private': serializer.toJson<bool>(private),
      'modifiedSecs': serializer.toJson<int?>(modifiedSecs),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'conflictContent': serializer.toJson<String?>(conflictContent),
      'conflictHash': serializer.toJson<String?>(conflictHash),
    };
  }

  NoteMirrorData copyWith({
    String? path,
    String? content,
    String? baseHash,
    String? localHash,
    bool? private,
    Value<int?> modifiedSecs = const Value.absent(),
    DateTime? updatedAt,
    Value<String?> conflictContent = const Value.absent(),
    Value<String?> conflictHash = const Value.absent(),
  }) => NoteMirrorData(
    path: path ?? this.path,
    content: content ?? this.content,
    baseHash: baseHash ?? this.baseHash,
    localHash: localHash ?? this.localHash,
    private: private ?? this.private,
    modifiedSecs: modifiedSecs.present ? modifiedSecs.value : this.modifiedSecs,
    updatedAt: updatedAt ?? this.updatedAt,
    conflictContent: conflictContent.present
        ? conflictContent.value
        : this.conflictContent,
    conflictHash: conflictHash.present ? conflictHash.value : this.conflictHash,
  );
  NoteMirrorData copyWithCompanion(NoteMirrorCompanion data) {
    return NoteMirrorData(
      path: data.path.present ? data.path.value : this.path,
      content: data.content.present ? data.content.value : this.content,
      baseHash: data.baseHash.present ? data.baseHash.value : this.baseHash,
      localHash: data.localHash.present ? data.localHash.value : this.localHash,
      private: data.private.present ? data.private.value : this.private,
      modifiedSecs: data.modifiedSecs.present
          ? data.modifiedSecs.value
          : this.modifiedSecs,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      conflictContent: data.conflictContent.present
          ? data.conflictContent.value
          : this.conflictContent,
      conflictHash: data.conflictHash.present
          ? data.conflictHash.value
          : this.conflictHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteMirrorData(')
          ..write('path: $path, ')
          ..write('content: $content, ')
          ..write('baseHash: $baseHash, ')
          ..write('localHash: $localHash, ')
          ..write('private: $private, ')
          ..write('modifiedSecs: $modifiedSecs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('conflictContent: $conflictContent, ')
          ..write('conflictHash: $conflictHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    path,
    content,
    baseHash,
    localHash,
    private,
    modifiedSecs,
    updatedAt,
    conflictContent,
    conflictHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteMirrorData &&
          other.path == this.path &&
          other.content == this.content &&
          other.baseHash == this.baseHash &&
          other.localHash == this.localHash &&
          other.private == this.private &&
          other.modifiedSecs == this.modifiedSecs &&
          other.updatedAt == this.updatedAt &&
          other.conflictContent == this.conflictContent &&
          other.conflictHash == this.conflictHash);
}

class NoteMirrorCompanion extends UpdateCompanion<NoteMirrorData> {
  final Value<String> path;
  final Value<String> content;
  final Value<String> baseHash;
  final Value<String> localHash;
  final Value<bool> private;
  final Value<int?> modifiedSecs;
  final Value<DateTime> updatedAt;
  final Value<String?> conflictContent;
  final Value<String?> conflictHash;
  final Value<int> rowid;
  const NoteMirrorCompanion({
    this.path = const Value.absent(),
    this.content = const Value.absent(),
    this.baseHash = const Value.absent(),
    this.localHash = const Value.absent(),
    this.private = const Value.absent(),
    this.modifiedSecs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.conflictContent = const Value.absent(),
    this.conflictHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteMirrorCompanion.insert({
    required String path,
    required String content,
    this.baseHash = const Value.absent(),
    this.localHash = const Value.absent(),
    this.private = const Value.absent(),
    this.modifiedSecs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.conflictContent = const Value.absent(),
    this.conflictHash = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       content = Value(content);
  static Insertable<NoteMirrorData> custom({
    Expression<String>? path,
    Expression<String>? content,
    Expression<String>? baseHash,
    Expression<String>? localHash,
    Expression<bool>? private,
    Expression<int>? modifiedSecs,
    Expression<DateTime>? updatedAt,
    Expression<String>? conflictContent,
    Expression<String>? conflictHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (content != null) 'content': content,
      if (baseHash != null) 'base_hash': baseHash,
      if (localHash != null) 'local_hash': localHash,
      if (private != null) 'private': private,
      if (modifiedSecs != null) 'modified_secs': modifiedSecs,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (conflictContent != null) 'conflict_content': conflictContent,
      if (conflictHash != null) 'conflict_hash': conflictHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteMirrorCompanion copyWith({
    Value<String>? path,
    Value<String>? content,
    Value<String>? baseHash,
    Value<String>? localHash,
    Value<bool>? private,
    Value<int?>? modifiedSecs,
    Value<DateTime>? updatedAt,
    Value<String?>? conflictContent,
    Value<String?>? conflictHash,
    Value<int>? rowid,
  }) {
    return NoteMirrorCompanion(
      path: path ?? this.path,
      content: content ?? this.content,
      baseHash: baseHash ?? this.baseHash,
      localHash: localHash ?? this.localHash,
      private: private ?? this.private,
      modifiedSecs: modifiedSecs ?? this.modifiedSecs,
      updatedAt: updatedAt ?? this.updatedAt,
      conflictContent: conflictContent ?? this.conflictContent,
      conflictHash: conflictHash ?? this.conflictHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (baseHash.present) {
      map['base_hash'] = Variable<String>(baseHash.value);
    }
    if (localHash.present) {
      map['local_hash'] = Variable<String>(localHash.value);
    }
    if (private.present) {
      map['private'] = Variable<bool>(private.value);
    }
    if (modifiedSecs.present) {
      map['modified_secs'] = Variable<int>(modifiedSecs.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (conflictContent.present) {
      map['conflict_content'] = Variable<String>(conflictContent.value);
    }
    if (conflictHash.present) {
      map['conflict_hash'] = Variable<String>(conflictHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteMirrorCompanion(')
          ..write('path: $path, ')
          ..write('content: $content, ')
          ..write('baseHash: $baseHash, ')
          ..write('localHash: $localHash, ')
          ..write('private: $private, ')
          ..write('modifiedSecs: $modifiedSecs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('conflictContent: $conflictContent, ')
          ..write('conflictHash: $conflictHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteOutboxTable extends NoteOutbox
    with TableInfo<$NoteOutboxTable, NoteOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _baseHashMeta = const VerificationMeta(
    'baseHash',
  );
  @override
  late final GeneratedColumn<String> baseHash = GeneratedColumn<String>(
    'base_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    path,
    kind,
    content,
    baseHash,
    createdAt,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('base_hash')) {
      context.handle(
        _baseHashMeta,
        baseHash.isAcceptableOrUnknown(data['base_hash']!, _baseHashMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteOutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      baseHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_hash'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $NoteOutboxTable createAlias(String alias) {
    return $NoteOutboxTable(attachedDatabase, alias);
  }
}

class NoteOutboxData extends DataClass implements Insertable<NoteOutboxData> {
  final String id;

  /// La nota, relativa a la bóveda.
  final String path;

  /// `save` o `delete`.
  final String kind;

  /// El texto a guardar. Vacío en un borrado.
  final String content;

  /// El hash con el que el teléfono vio la nota. Vacío significa "nota nueva":
  /// la PC la crea y **nunca pisa** una que ya exista.
  final String baseHash;

  /// Para mandar en el mismo orden en que se escribieron. Aplicar una tanda
  /// desordenada dejaría el espejo diciendo algo distinto de la bóveda.
  final DateTime createdAt;

  /// Cuántas veces se intentó. Sirve para no reintentar en bucle algo que la PC
  /// rechaza siempre, y para poder decirlo en pantalla.
  final int attempts;

  /// Lo último que contestó la PC cuando falló. `null` mientras no haya fallado.
  final String? lastError;
  const NoteOutboxData({
    required this.id,
    required this.path,
    required this.kind,
    required this.content,
    required this.baseHash,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['path'] = Variable<String>(path);
    map['kind'] = Variable<String>(kind);
    map['content'] = Variable<String>(content);
    map['base_hash'] = Variable<String>(baseHash);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  NoteOutboxCompanion toCompanion(bool nullToAbsent) {
    return NoteOutboxCompanion(
      id: Value(id),
      path: Value(path),
      kind: Value(kind),
      content: Value(content),
      baseHash: Value(baseHash),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory NoteOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteOutboxData(
      id: serializer.fromJson<String>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      kind: serializer.fromJson<String>(json['kind']),
      content: serializer.fromJson<String>(json['content']),
      baseHash: serializer.fromJson<String>(json['baseHash']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'path': serializer.toJson<String>(path),
      'kind': serializer.toJson<String>(kind),
      'content': serializer.toJson<String>(content),
      'baseHash': serializer.toJson<String>(baseHash),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  NoteOutboxData copyWith({
    String? id,
    String? path,
    String? kind,
    String? content,
    String? baseHash,
    DateTime? createdAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => NoteOutboxData(
    id: id ?? this.id,
    path: path ?? this.path,
    kind: kind ?? this.kind,
    content: content ?? this.content,
    baseHash: baseHash ?? this.baseHash,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  NoteOutboxData copyWithCompanion(NoteOutboxCompanion data) {
    return NoteOutboxData(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      kind: data.kind.present ? data.kind.value : this.kind,
      content: data.content.present ? data.content.value : this.content,
      baseHash: data.baseHash.present ? data.baseHash.value : this.baseHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteOutboxData(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('kind: $kind, ')
          ..write('content: $content, ')
          ..write('baseHash: $baseHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    path,
    kind,
    content,
    baseHash,
    createdAt,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteOutboxData &&
          other.id == this.id &&
          other.path == this.path &&
          other.kind == this.kind &&
          other.content == this.content &&
          other.baseHash == this.baseHash &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class NoteOutboxCompanion extends UpdateCompanion<NoteOutboxData> {
  final Value<String> id;
  final Value<String> path;
  final Value<String> kind;
  final Value<String> content;
  final Value<String> baseHash;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> rowid;
  const NoteOutboxCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.kind = const Value.absent(),
    this.content = const Value.absent(),
    this.baseHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String path,
    required String kind,
    this.content = const Value.absent(),
    this.baseHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       kind = Value(kind);
  static Insertable<NoteOutboxData> custom({
    Expression<String>? id,
    Expression<String>? path,
    Expression<String>? kind,
    Expression<String>? content,
    Expression<String>? baseHash,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (kind != null) 'kind': kind,
      if (content != null) 'content': content,
      if (baseHash != null) 'base_hash': baseHash,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteOutboxCompanion copyWith({
    Value<String>? id,
    Value<String>? path,
    Value<String>? kind,
    Value<String>? content,
    Value<String>? baseHash,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return NoteOutboxCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      kind: kind ?? this.kind,
      content: content ?? this.content,
      baseHash: baseHash ?? this.baseHash,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (baseHash.present) {
      map['base_hash'] = Variable<String>(baseHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteOutboxCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('kind: $kind, ')
          ..write('content: $content, ')
          ..write('baseHash: $baseHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$NexoDeckDatabase extends GeneratedDatabase {
  _$NexoDeckDatabase(QueryExecutor e) : super(e);
  $NexoDeckDatabaseManager get managers => $NexoDeckDatabaseManager(this);
  late final $ActionGroupsTable actionGroups = $ActionGroupsTable(this);
  late final $ActionsTableTable actionsTable = $ActionsTableTable(this);
  late final $ActionParametersTable actionParameters = $ActionParametersTable(
    this,
  );
  late final $MacroStepsTable macroSteps = $MacroStepsTable(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $ProfileActionsTable profileActions = $ProfileActionsTable(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $AlertRulesTable alertRules = $AlertRulesTable(this);
  late final $HardwareHistoryTable hardwareHistory = $HardwareHistoryTable(
    this,
  );
  late final $SecretsRefsTable secretsRefs = $SecretsRefsTable(this);
  late final $WindowLayoutsTable windowLayouts = $WindowLayoutsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $HubSubscriptionsTable hubSubscriptions = $HubSubscriptionsTable(
    this,
  );
  late final $HubMessagesTable hubMessages = $HubMessagesTable(this);
  late final $ChatConversationsTable chatConversations =
      $ChatConversationsTable(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $NoteMirrorTable noteMirror = $NoteMirrorTable(this);
  late final $NoteOutboxTable noteOutbox = $NoteOutboxTable(this);
  late final Index idxActionParametersActionId = Index(
    'idx_action_parameters_action_id',
    'CREATE INDEX idx_action_parameters_action_id ON action_parameters (action_id)',
  );
  late final Index idxMacroStepsMacroActionOrder = Index(
    'idx_macro_steps_macro_action_order',
    'CREATE INDEX idx_macro_steps_macro_action_order ON macro_steps (macro_action_id, order_index)',
  );
  late final Index idxProfileActionsProfileOrder = Index(
    'idx_profile_actions_profile_order',
    'CREATE INDEX idx_profile_actions_profile_order ON profile_actions (profile_id, order_index)',
  );
  late final Index idxDevicesCertFingerprint = Index(
    'idx_devices_cert_fingerprint',
    'CREATE INDEX idx_devices_cert_fingerprint ON devices (cert_fingerprint)',
  );
  late final Index idxHardwareHistoryTimestamp = Index(
    'idx_hardware_history_timestamp',
    'CREATE INDEX idx_hardware_history_timestamp ON hardware_history (timestamp)',
  );
  late final Index idxHubMessagesSubscriptionReceived = Index(
    'idx_hub_messages_subscription_received',
    'CREATE INDEX idx_hub_messages_subscription_received ON hub_messages (subscription_id, received_at)',
  );
  late final ActionsDao actionsDao = ActionsDao(this as NexoDeckDatabase);
  late final ActionParametersDao actionParametersDao = ActionParametersDao(
    this as NexoDeckDatabase,
  );
  late final MacroStepsDao macroStepsDao = MacroStepsDao(
    this as NexoDeckDatabase,
  );
  late final ProfilesDao profilesDao = ProfilesDao(this as NexoDeckDatabase);
  late final ProfileActionsDao profileActionsDao = ProfileActionsDao(
    this as NexoDeckDatabase,
  );
  late final DevicesDao devicesDao = DevicesDao(this as NexoDeckDatabase);
  late final AlertRulesDao alertRulesDao = AlertRulesDao(
    this as NexoDeckDatabase,
  );
  late final HardwareHistoryDao hardwareHistoryDao = HardwareHistoryDao(
    this as NexoDeckDatabase,
  );
  late final SecretsRefsDao secretsRefsDao = SecretsRefsDao(
    this as NexoDeckDatabase,
  );
  late final WindowLayoutsDao windowLayoutsDao = WindowLayoutsDao(
    this as NexoDeckDatabase,
  );
  late final AppSettingsDao appSettingsDao = AppSettingsDao(
    this as NexoDeckDatabase,
  );
  late final ActionGroupsDao actionGroupsDao = ActionGroupsDao(
    this as NexoDeckDatabase,
  );
  late final HubSubscriptionsDao hubSubscriptionsDao = HubSubscriptionsDao(
    this as NexoDeckDatabase,
  );
  late final HubMessagesDao hubMessagesDao = HubMessagesDao(
    this as NexoDeckDatabase,
  );
  late final ChatConversationsDao chatConversationsDao = ChatConversationsDao(
    this as NexoDeckDatabase,
  );
  late final NotesMirrorDao notesMirrorDao = NotesMirrorDao(
    this as NexoDeckDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    actionGroups,
    actionsTable,
    actionParameters,
    macroSteps,
    profiles,
    profileActions,
    devices,
    alertRules,
    hardwareHistory,
    secretsRefs,
    windowLayouts,
    appSettings,
    hubSubscriptions,
    hubMessages,
    chatConversations,
    chatMessages,
    noteMirror,
    noteOutbox,
    idxActionParametersActionId,
    idxMacroStepsMacroActionOrder,
    idxProfileActionsProfileOrder,
    idxDevicesCertFingerprint,
    idxHardwareHistoryTimestamp,
    idxHubMessagesSubscriptionReceived,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'action_groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('actions_table', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions_table',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('action_parameters', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions_table',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('macro_steps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions_table',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('macro_steps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'profiles',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('profile_actions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions_table',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('profile_actions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'hub_subscriptions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('hub_messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'chat_conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('chat_messages', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ActionGroupsTableCreateCompanionBuilder =
    ActionGroupsCompanion Function({
      Value<String> id,
      required String name,
      Value<String> icon,
      Value<String> colorHex,
      Value<int> orderIndex,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ActionGroupsTableUpdateCompanionBuilder =
    ActionGroupsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> icon,
      Value<String> colorHex,
      Value<int> orderIndex,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ActionGroupsTableReferences
    extends
        BaseReferences<_$NexoDeckDatabase, $ActionGroupsTable, ActionGroup> {
  $$ActionGroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ActionsTableTable, List<ActionsTableData>>
  _actionsTableRefsTable(_$NexoDeckDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionsTable,
        aliasName: 'action_groups__id__actions_table__group_id',
      );

  $$ActionsTableTableProcessedTableManager get actionsTableRefs {
    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_actionsTableRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActionGroupsTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $ActionGroupsTable> {
  $$ActionGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> actionsTableRefs(
    Expression<bool> Function($$ActionsTableTableFilterComposer f) f,
  ) {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActionGroupsTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $ActionGroupsTable> {
  $$ActionGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActionGroupsTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $ActionGroupsTable> {
  $$ActionGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> actionsTableRefs<T extends Object>(
    Expression<T> Function($$ActionsTableTableAnnotationComposer a) f,
  ) {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActionGroupsTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $ActionGroupsTable,
          ActionGroup,
          $$ActionGroupsTableFilterComposer,
          $$ActionGroupsTableOrderingComposer,
          $$ActionGroupsTableAnnotationComposer,
          $$ActionGroupsTableCreateCompanionBuilder,
          $$ActionGroupsTableUpdateCompanionBuilder,
          (ActionGroup, $$ActionGroupsTableReferences),
          ActionGroup,
          PrefetchHooks Function({bool actionsTableRefs})
        > {
  $$ActionGroupsTableTableManager(
    _$NexoDeckDatabase db,
    $ActionGroupsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> colorHex = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionGroupsCompanion(
                id: id,
                name: name,
                icon: icon,
                colorHex: colorHex,
                orderIndex: orderIndex,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String name,
                Value<String> icon = const Value.absent(),
                Value<String> colorHex = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionGroupsCompanion.insert(
                id: id,
                name: name,
                icon: icon,
                colorHex: colorHex,
                orderIndex: orderIndex,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActionGroupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({actionsTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (actionsTableRefs) db.actionsTable],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (actionsTableRefs)
                    await $_getPrefetchedData<
                      ActionGroup,
                      $ActionGroupsTable,
                      ActionsTableData
                    >(
                      currentTable: table,
                      referencedTable: $$ActionGroupsTableReferences
                          ._actionsTableRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ActionGroupsTableReferences(
                            db,
                            table,
                            p0,
                          ).actionsTableRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.groupId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ActionGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $ActionGroupsTable,
      ActionGroup,
      $$ActionGroupsTableFilterComposer,
      $$ActionGroupsTableOrderingComposer,
      $$ActionGroupsTableAnnotationComposer,
      $$ActionGroupsTableCreateCompanionBuilder,
      $$ActionGroupsTableUpdateCompanionBuilder,
      (ActionGroup, $$ActionGroupsTableReferences),
      ActionGroup,
      PrefetchHooks Function({bool actionsTableRefs})
    >;
typedef $$ActionsTableTableCreateCompanionBuilder =
    ActionsTableCompanion Function({
      Value<String> id,
      required String name,
      Value<String?> description,
      Value<String> icon,
      Value<String> colorHex,
      required ActionType actionType,
      Value<String?> commandTemplate,
      Value<bool> requiresAdmin,
      Value<TerminalType?> terminalType,
      Value<bool> showTerminalWindow,
      Value<bool> pasteToActiveWindow,
      Value<String?> autoSubscribeBaseUrl,
      Value<String?> autoSubscribeHubPath,
      Value<String?> autoSubscribeInvokeMethod,
      Value<String?> autoSubscribeJsonField,
      Value<bool> autoSubscribeAllowInvalidCert,
      Value<bool> isFavorite,
      Value<String?> groupId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ActionsTableTableUpdateCompanionBuilder =
    ActionsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<String> icon,
      Value<String> colorHex,
      Value<ActionType> actionType,
      Value<String?> commandTemplate,
      Value<bool> requiresAdmin,
      Value<TerminalType?> terminalType,
      Value<bool> showTerminalWindow,
      Value<bool> pasteToActiveWindow,
      Value<String?> autoSubscribeBaseUrl,
      Value<String?> autoSubscribeHubPath,
      Value<String?> autoSubscribeInvokeMethod,
      Value<String?> autoSubscribeJsonField,
      Value<bool> autoSubscribeAllowInvalidCert,
      Value<bool> isFavorite,
      Value<String?> groupId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ActionsTableTableReferences
    extends
        BaseReferences<
          _$NexoDeckDatabase,
          $ActionsTableTable,
          ActionsTableData
        > {
  $$ActionsTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ActionGroupsTable _groupIdTable(_$NexoDeckDatabase db) =>
      db.actionGroups.createAlias('actions_table__group_id__action_groups__id');

  $$ActionGroupsTableProcessedTableManager? get groupId {
    final $_column = $_itemColumn<String>('group_id');
    if ($_column == null) return null;
    final manager = $$ActionGroupsTableTableManager(
      $_db,
      $_db.actionGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ActionParametersTable, List<ActionParameter>>
  _actionParametersRefsTable(_$NexoDeckDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionParameters,
        aliasName: 'actions_table__id__action_parameters__action_id',
      );

  $$ActionParametersTableProcessedTableManager get actionParametersRefs {
    final manager = $$ActionParametersTableTableManager(
      $_db,
      $_db.actionParameters,
    ).filter((f) => f.actionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _actionParametersRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MacroStepsTable, List<MacroStep>>
  _macroStepsAsContainerTable(_$NexoDeckDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.macroSteps,
        aliasName: 'actions_table__id__macro_steps__macro_action_id',
      );

  $$MacroStepsTableProcessedTableManager get macroStepsAsContainer {
    final manager = $$MacroStepsTableTableManager(
      $_db,
      $_db.macroSteps,
    ).filter((f) => f.macroActionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _macroStepsAsContainerTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MacroStepsTable, List<MacroStep>>
  _macroStepsAsStepTable(_$NexoDeckDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.macroSteps,
        aliasName: 'actions_table__id__macro_steps__step_action_id',
      );

  $$MacroStepsTableProcessedTableManager get macroStepsAsStep {
    final manager = $$MacroStepsTableTableManager(
      $_db,
      $_db.macroSteps,
    ).filter((f) => f.stepActionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_macroStepsAsStepTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProfileActionsTable, List<ProfileAction>>
  _profileActionsRefsTable(_$NexoDeckDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.profileActions,
        aliasName: 'actions_table__id__profile_actions__action_id',
      );

  $$ProfileActionsTableProcessedTableManager get profileActionsRefs {
    final manager = $$ProfileActionsTableTableManager(
      $_db,
      $_db.profileActions,
    ).filter((f) => f.actionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_profileActionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActionsTableTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $ActionsTableTable> {
  $$ActionsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ActionType, ActionType, String>
  get actionType => $composableBuilder(
    column: $table.actionType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get commandTemplate => $composableBuilder(
    column: $table.commandTemplate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresAdmin => $composableBuilder(
    column: $table.requiresAdmin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TerminalType?, TerminalType, String>
  get terminalType => $composableBuilder(
    column: $table.terminalType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get showTerminalWindow => $composableBuilder(
    column: $table.showTerminalWindow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pasteToActiveWindow => $composableBuilder(
    column: $table.pasteToActiveWindow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get autoSubscribeBaseUrl => $composableBuilder(
    column: $table.autoSubscribeBaseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get autoSubscribeHubPath => $composableBuilder(
    column: $table.autoSubscribeHubPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get autoSubscribeInvokeMethod => $composableBuilder(
    column: $table.autoSubscribeInvokeMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get autoSubscribeJsonField => $composableBuilder(
    column: $table.autoSubscribeJsonField,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoSubscribeAllowInvalidCert => $composableBuilder(
    column: $table.autoSubscribeAllowInvalidCert,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ActionGroupsTableFilterComposer get groupId {
    final $$ActionGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.actionGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionGroupsTableFilterComposer(
            $db: $db,
            $table: $db.actionGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> actionParametersRefs(
    Expression<bool> Function($$ActionParametersTableFilterComposer f) f,
  ) {
    final $$ActionParametersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionParameters,
      getReferencedColumn: (t) => t.actionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionParametersTableFilterComposer(
            $db: $db,
            $table: $db.actionParameters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> macroStepsAsContainer(
    Expression<bool> Function($$MacroStepsTableFilterComposer f) f,
  ) {
    final $$MacroStepsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.macroSteps,
      getReferencedColumn: (t) => t.macroActionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MacroStepsTableFilterComposer(
            $db: $db,
            $table: $db.macroSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> macroStepsAsStep(
    Expression<bool> Function($$MacroStepsTableFilterComposer f) f,
  ) {
    final $$MacroStepsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.macroSteps,
      getReferencedColumn: (t) => t.stepActionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MacroStepsTableFilterComposer(
            $db: $db,
            $table: $db.macroSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> profileActionsRefs(
    Expression<bool> Function($$ProfileActionsTableFilterComposer f) f,
  ) {
    final $$ProfileActionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.profileActions,
      getReferencedColumn: (t) => t.actionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfileActionsTableFilterComposer(
            $db: $db,
            $table: $db.profileActions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActionsTableTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $ActionsTableTable> {
  $$ActionsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actionType => $composableBuilder(
    column: $table.actionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commandTemplate => $composableBuilder(
    column: $table.commandTemplate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresAdmin => $composableBuilder(
    column: $table.requiresAdmin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get terminalType => $composableBuilder(
    column: $table.terminalType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showTerminalWindow => $composableBuilder(
    column: $table.showTerminalWindow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pasteToActiveWindow => $composableBuilder(
    column: $table.pasteToActiveWindow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get autoSubscribeBaseUrl => $composableBuilder(
    column: $table.autoSubscribeBaseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get autoSubscribeHubPath => $composableBuilder(
    column: $table.autoSubscribeHubPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get autoSubscribeInvokeMethod => $composableBuilder(
    column: $table.autoSubscribeInvokeMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get autoSubscribeJsonField => $composableBuilder(
    column: $table.autoSubscribeJsonField,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoSubscribeAllowInvalidCert => $composableBuilder(
    column: $table.autoSubscribeAllowInvalidCert,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActionGroupsTableOrderingComposer get groupId {
    final $$ActionGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.actionGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.actionGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionsTableTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $ActionsTableTable> {
  $$ActionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ActionType, String> get actionType =>
      $composableBuilder(
        column: $table.actionType,
        builder: (column) => column,
      );

  GeneratedColumn<String> get commandTemplate => $composableBuilder(
    column: $table.commandTemplate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requiresAdmin => $composableBuilder(
    column: $table.requiresAdmin,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TerminalType?, String> get terminalType =>
      $composableBuilder(
        column: $table.terminalType,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get showTerminalWindow => $composableBuilder(
    column: $table.showTerminalWindow,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get pasteToActiveWindow => $composableBuilder(
    column: $table.pasteToActiveWindow,
    builder: (column) => column,
  );

  GeneratedColumn<String> get autoSubscribeBaseUrl => $composableBuilder(
    column: $table.autoSubscribeBaseUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get autoSubscribeHubPath => $composableBuilder(
    column: $table.autoSubscribeHubPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get autoSubscribeInvokeMethod => $composableBuilder(
    column: $table.autoSubscribeInvokeMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get autoSubscribeJsonField => $composableBuilder(
    column: $table.autoSubscribeJsonField,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoSubscribeAllowInvalidCert => $composableBuilder(
    column: $table.autoSubscribeAllowInvalidCert,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ActionGroupsTableAnnotationComposer get groupId {
    final $$ActionGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.actionGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.actionGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> actionParametersRefs<T extends Object>(
    Expression<T> Function($$ActionParametersTableAnnotationComposer a) f,
  ) {
    final $$ActionParametersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionParameters,
      getReferencedColumn: (t) => t.actionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionParametersTableAnnotationComposer(
            $db: $db,
            $table: $db.actionParameters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> macroStepsAsContainer<T extends Object>(
    Expression<T> Function($$MacroStepsTableAnnotationComposer a) f,
  ) {
    final $$MacroStepsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.macroSteps,
      getReferencedColumn: (t) => t.macroActionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MacroStepsTableAnnotationComposer(
            $db: $db,
            $table: $db.macroSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> macroStepsAsStep<T extends Object>(
    Expression<T> Function($$MacroStepsTableAnnotationComposer a) f,
  ) {
    final $$MacroStepsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.macroSteps,
      getReferencedColumn: (t) => t.stepActionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MacroStepsTableAnnotationComposer(
            $db: $db,
            $table: $db.macroSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> profileActionsRefs<T extends Object>(
    Expression<T> Function($$ProfileActionsTableAnnotationComposer a) f,
  ) {
    final $$ProfileActionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.profileActions,
      getReferencedColumn: (t) => t.actionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfileActionsTableAnnotationComposer(
            $db: $db,
            $table: $db.profileActions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActionsTableTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $ActionsTableTable,
          ActionsTableData,
          $$ActionsTableTableFilterComposer,
          $$ActionsTableTableOrderingComposer,
          $$ActionsTableTableAnnotationComposer,
          $$ActionsTableTableCreateCompanionBuilder,
          $$ActionsTableTableUpdateCompanionBuilder,
          (ActionsTableData, $$ActionsTableTableReferences),
          ActionsTableData,
          PrefetchHooks Function({
            bool groupId,
            bool actionParametersRefs,
            bool macroStepsAsContainer,
            bool macroStepsAsStep,
            bool profileActionsRefs,
          })
        > {
  $$ActionsTableTableTableManager(
    _$NexoDeckDatabase db,
    $ActionsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> colorHex = const Value.absent(),
                Value<ActionType> actionType = const Value.absent(),
                Value<String?> commandTemplate = const Value.absent(),
                Value<bool> requiresAdmin = const Value.absent(),
                Value<TerminalType?> terminalType = const Value.absent(),
                Value<bool> showTerminalWindow = const Value.absent(),
                Value<bool> pasteToActiveWindow = const Value.absent(),
                Value<String?> autoSubscribeBaseUrl = const Value.absent(),
                Value<String?> autoSubscribeHubPath = const Value.absent(),
                Value<String?> autoSubscribeInvokeMethod = const Value.absent(),
                Value<String?> autoSubscribeJsonField = const Value.absent(),
                Value<bool> autoSubscribeAllowInvalidCert =
                    const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionsTableCompanion(
                id: id,
                name: name,
                description: description,
                icon: icon,
                colorHex: colorHex,
                actionType: actionType,
                commandTemplate: commandTemplate,
                requiresAdmin: requiresAdmin,
                terminalType: terminalType,
                showTerminalWindow: showTerminalWindow,
                pasteToActiveWindow: pasteToActiveWindow,
                autoSubscribeBaseUrl: autoSubscribeBaseUrl,
                autoSubscribeHubPath: autoSubscribeHubPath,
                autoSubscribeInvokeMethod: autoSubscribeInvokeMethod,
                autoSubscribeJsonField: autoSubscribeJsonField,
                autoSubscribeAllowInvalidCert: autoSubscribeAllowInvalidCert,
                isFavorite: isFavorite,
                groupId: groupId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> colorHex = const Value.absent(),
                required ActionType actionType,
                Value<String?> commandTemplate = const Value.absent(),
                Value<bool> requiresAdmin = const Value.absent(),
                Value<TerminalType?> terminalType = const Value.absent(),
                Value<bool> showTerminalWindow = const Value.absent(),
                Value<bool> pasteToActiveWindow = const Value.absent(),
                Value<String?> autoSubscribeBaseUrl = const Value.absent(),
                Value<String?> autoSubscribeHubPath = const Value.absent(),
                Value<String?> autoSubscribeInvokeMethod = const Value.absent(),
                Value<String?> autoSubscribeJsonField = const Value.absent(),
                Value<bool> autoSubscribeAllowInvalidCert =
                    const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionsTableCompanion.insert(
                id: id,
                name: name,
                description: description,
                icon: icon,
                colorHex: colorHex,
                actionType: actionType,
                commandTemplate: commandTemplate,
                requiresAdmin: requiresAdmin,
                terminalType: terminalType,
                showTerminalWindow: showTerminalWindow,
                pasteToActiveWindow: pasteToActiveWindow,
                autoSubscribeBaseUrl: autoSubscribeBaseUrl,
                autoSubscribeHubPath: autoSubscribeHubPath,
                autoSubscribeInvokeMethod: autoSubscribeInvokeMethod,
                autoSubscribeJsonField: autoSubscribeJsonField,
                autoSubscribeAllowInvalidCert: autoSubscribeAllowInvalidCert,
                isFavorite: isFavorite,
                groupId: groupId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActionsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                groupId = false,
                actionParametersRefs = false,
                macroStepsAsContainer = false,
                macroStepsAsStep = false,
                profileActionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (actionParametersRefs) db.actionParameters,
                    if (macroStepsAsContainer) db.macroSteps,
                    if (macroStepsAsStep) db.macroSteps,
                    if (profileActionsRefs) db.profileActions,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (groupId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.groupId,
                                    referencedTable:
                                        $$ActionsTableTableReferences
                                            ._groupIdTable(db),
                                    referencedColumn:
                                        $$ActionsTableTableReferences
                                            ._groupIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (actionParametersRefs)
                        await $_getPrefetchedData<
                          ActionsTableData,
                          $ActionsTableTable,
                          ActionParameter
                        >(
                          currentTable: table,
                          referencedTable: $$ActionsTableTableReferences
                              ._actionParametersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).actionParametersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.actionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (macroStepsAsContainer)
                        await $_getPrefetchedData<
                          ActionsTableData,
                          $ActionsTableTable,
                          MacroStep
                        >(
                          currentTable: table,
                          referencedTable: $$ActionsTableTableReferences
                              ._macroStepsAsContainerTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).macroStepsAsContainer,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.macroActionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (macroStepsAsStep)
                        await $_getPrefetchedData<
                          ActionsTableData,
                          $ActionsTableTable,
                          MacroStep
                        >(
                          currentTable: table,
                          referencedTable: $$ActionsTableTableReferences
                              ._macroStepsAsStepTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).macroStepsAsStep,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.stepActionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (profileActionsRefs)
                        await $_getPrefetchedData<
                          ActionsTableData,
                          $ActionsTableTable,
                          ProfileAction
                        >(
                          currentTable: table,
                          referencedTable: $$ActionsTableTableReferences
                              ._profileActionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).profileActionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.actionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ActionsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $ActionsTableTable,
      ActionsTableData,
      $$ActionsTableTableFilterComposer,
      $$ActionsTableTableOrderingComposer,
      $$ActionsTableTableAnnotationComposer,
      $$ActionsTableTableCreateCompanionBuilder,
      $$ActionsTableTableUpdateCompanionBuilder,
      (ActionsTableData, $$ActionsTableTableReferences),
      ActionsTableData,
      PrefetchHooks Function({
        bool groupId,
        bool actionParametersRefs,
        bool macroStepsAsContainer,
        bool macroStepsAsStep,
        bool profileActionsRefs,
      })
    >;
typedef $$ActionParametersTableCreateCompanionBuilder =
    ActionParametersCompanion Function({
      Value<String> id,
      required String actionId,
      required String key,
      required String label,
      Value<ParamInputType> inputType,
      Value<String?> defaultValue,
      Value<String?> optionsJson,
      Value<int> orderIndex,
      Value<int> rowid,
    });
typedef $$ActionParametersTableUpdateCompanionBuilder =
    ActionParametersCompanion Function({
      Value<String> id,
      Value<String> actionId,
      Value<String> key,
      Value<String> label,
      Value<ParamInputType> inputType,
      Value<String?> defaultValue,
      Value<String?> optionsJson,
      Value<int> orderIndex,
      Value<int> rowid,
    });

final class $$ActionParametersTableReferences
    extends
        BaseReferences<
          _$NexoDeckDatabase,
          $ActionParametersTable,
          ActionParameter
        > {
  $$ActionParametersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActionsTableTable _actionIdTable(_$NexoDeckDatabase db) => db
      .actionsTable
      .createAlias('action_parameters__action_id__actions_table__id');

  $$ActionsTableTableProcessedTableManager get actionId {
    final $_column = $_itemColumn<String>('action_id')!;

    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_actionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActionParametersTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $ActionParametersTable> {
  $$ActionParametersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ParamInputType, ParamInputType, String>
  get inputType => $composableBuilder(
    column: $table.inputType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get defaultValue => $composableBuilder(
    column: $table.defaultValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  $$ActionsTableTableFilterComposer get actionId {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionParametersTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $ActionParametersTable> {
  $$ActionParametersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputType => $composableBuilder(
    column: $table.inputType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultValue => $composableBuilder(
    column: $table.defaultValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActionsTableTableOrderingComposer get actionId {
    final $$ActionsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableOrderingComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionParametersTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $ActionParametersTable> {
  $$ActionParametersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ParamInputType, String> get inputType =>
      $composableBuilder(column: $table.inputType, builder: (column) => column);

  GeneratedColumn<String> get defaultValue => $composableBuilder(
    column: $table.defaultValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  $$ActionsTableTableAnnotationComposer get actionId {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionParametersTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $ActionParametersTable,
          ActionParameter,
          $$ActionParametersTableFilterComposer,
          $$ActionParametersTableOrderingComposer,
          $$ActionParametersTableAnnotationComposer,
          $$ActionParametersTableCreateCompanionBuilder,
          $$ActionParametersTableUpdateCompanionBuilder,
          (ActionParameter, $$ActionParametersTableReferences),
          ActionParameter,
          PrefetchHooks Function({bool actionId})
        > {
  $$ActionParametersTableTableManager(
    _$NexoDeckDatabase db,
    $ActionParametersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionParametersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionParametersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionParametersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> actionId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<ParamInputType> inputType = const Value.absent(),
                Value<String?> defaultValue = const Value.absent(),
                Value<String?> optionsJson = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionParametersCompanion(
                id: id,
                actionId: actionId,
                key: key,
                label: label,
                inputType: inputType,
                defaultValue: defaultValue,
                optionsJson: optionsJson,
                orderIndex: orderIndex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String actionId,
                required String key,
                required String label,
                Value<ParamInputType> inputType = const Value.absent(),
                Value<String?> defaultValue = const Value.absent(),
                Value<String?> optionsJson = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionParametersCompanion.insert(
                id: id,
                actionId: actionId,
                key: key,
                label: label,
                inputType: inputType,
                defaultValue: defaultValue,
                optionsJson: optionsJson,
                orderIndex: orderIndex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActionParametersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({actionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (actionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.actionId,
                                referencedTable:
                                    $$ActionParametersTableReferences
                                        ._actionIdTable(db),
                                referencedColumn:
                                    $$ActionParametersTableReferences
                                        ._actionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ActionParametersTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $ActionParametersTable,
      ActionParameter,
      $$ActionParametersTableFilterComposer,
      $$ActionParametersTableOrderingComposer,
      $$ActionParametersTableAnnotationComposer,
      $$ActionParametersTableCreateCompanionBuilder,
      $$ActionParametersTableUpdateCompanionBuilder,
      (ActionParameter, $$ActionParametersTableReferences),
      ActionParameter,
      PrefetchHooks Function({bool actionId})
    >;
typedef $$MacroStepsTableCreateCompanionBuilder =
    MacroStepsCompanion Function({
      Value<String> id,
      required String macroActionId,
      required String stepActionId,
      required int orderIndex,
      Value<int> delayMsAfter,
      Value<int> rowid,
    });
typedef $$MacroStepsTableUpdateCompanionBuilder =
    MacroStepsCompanion Function({
      Value<String> id,
      Value<String> macroActionId,
      Value<String> stepActionId,
      Value<int> orderIndex,
      Value<int> delayMsAfter,
      Value<int> rowid,
    });

final class $$MacroStepsTableReferences
    extends BaseReferences<_$NexoDeckDatabase, $MacroStepsTable, MacroStep> {
  $$MacroStepsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ActionsTableTable _macroActionIdTable(_$NexoDeckDatabase db) => db
      .actionsTable
      .createAlias('macro_steps__macro_action_id__actions_table__id');

  $$ActionsTableTableProcessedTableManager get macroActionId {
    final $_column = $_itemColumn<String>('macro_action_id')!;

    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_macroActionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ActionsTableTable _stepActionIdTable(_$NexoDeckDatabase db) => db
      .actionsTable
      .createAlias('macro_steps__step_action_id__actions_table__id');

  $$ActionsTableTableProcessedTableManager get stepActionId {
    final $_column = $_itemColumn<String>('step_action_id')!;

    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_stepActionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MacroStepsTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $MacroStepsTable> {
  $$MacroStepsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get delayMsAfter => $composableBuilder(
    column: $table.delayMsAfter,
    builder: (column) => ColumnFilters(column),
  );

  $$ActionsTableTableFilterComposer get macroActionId {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.macroActionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionsTableTableFilterComposer get stepActionId {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stepActionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MacroStepsTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $MacroStepsTable> {
  $$MacroStepsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get delayMsAfter => $composableBuilder(
    column: $table.delayMsAfter,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActionsTableTableOrderingComposer get macroActionId {
    final $$ActionsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.macroActionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableOrderingComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionsTableTableOrderingComposer get stepActionId {
    final $$ActionsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stepActionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableOrderingComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MacroStepsTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $MacroStepsTable> {
  $$MacroStepsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get delayMsAfter => $composableBuilder(
    column: $table.delayMsAfter,
    builder: (column) => column,
  );

  $$ActionsTableTableAnnotationComposer get macroActionId {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.macroActionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionsTableTableAnnotationComposer get stepActionId {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stepActionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MacroStepsTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $MacroStepsTable,
          MacroStep,
          $$MacroStepsTableFilterComposer,
          $$MacroStepsTableOrderingComposer,
          $$MacroStepsTableAnnotationComposer,
          $$MacroStepsTableCreateCompanionBuilder,
          $$MacroStepsTableUpdateCompanionBuilder,
          (MacroStep, $$MacroStepsTableReferences),
          MacroStep,
          PrefetchHooks Function({bool macroActionId, bool stepActionId})
        > {
  $$MacroStepsTableTableManager(_$NexoDeckDatabase db, $MacroStepsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MacroStepsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MacroStepsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MacroStepsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> macroActionId = const Value.absent(),
                Value<String> stepActionId = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<int> delayMsAfter = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MacroStepsCompanion(
                id: id,
                macroActionId: macroActionId,
                stepActionId: stepActionId,
                orderIndex: orderIndex,
                delayMsAfter: delayMsAfter,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String macroActionId,
                required String stepActionId,
                required int orderIndex,
                Value<int> delayMsAfter = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MacroStepsCompanion.insert(
                id: id,
                macroActionId: macroActionId,
                stepActionId: stepActionId,
                orderIndex: orderIndex,
                delayMsAfter: delayMsAfter,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MacroStepsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({macroActionId = false, stepActionId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (macroActionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.macroActionId,
                                    referencedTable: $$MacroStepsTableReferences
                                        ._macroActionIdTable(db),
                                    referencedColumn:
                                        $$MacroStepsTableReferences
                                            ._macroActionIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (stepActionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.stepActionId,
                                    referencedTable: $$MacroStepsTableReferences
                                        ._stepActionIdTable(db),
                                    referencedColumn:
                                        $$MacroStepsTableReferences
                                            ._stepActionIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$MacroStepsTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $MacroStepsTable,
      MacroStep,
      $$MacroStepsTableFilterComposer,
      $$MacroStepsTableOrderingComposer,
      $$MacroStepsTableAnnotationComposer,
      $$MacroStepsTableCreateCompanionBuilder,
      $$MacroStepsTableUpdateCompanionBuilder,
      (MacroStep, $$MacroStepsTableReferences),
      MacroStep,
      PrefetchHooks Function({bool macroActionId, bool stepActionId})
    >;
typedef $$ProfilesTableCreateCompanionBuilder =
    ProfilesCompanion Function({
      Value<String> id,
      required String name,
      Value<String> icon,
      Value<String> colorHex,
      Value<bool> isDefault,
      Value<String?> autoDetectProcess,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ProfilesTableUpdateCompanionBuilder =
    ProfilesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> icon,
      Value<String> colorHex,
      Value<bool> isDefault,
      Value<String?> autoDetectProcess,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ProfilesTableReferences
    extends BaseReferences<_$NexoDeckDatabase, $ProfilesTable, Profile> {
  $$ProfilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProfileActionsTable, List<ProfileAction>>
  _profileActionsRefsTable(_$NexoDeckDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.profileActions,
        aliasName: 'profiles__id__profile_actions__profile_id',
      );

  $$ProfileActionsTableProcessedTableManager get profileActionsRefs {
    final manager = $$ProfileActionsTableTableManager(
      $_db,
      $_db.profileActions,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_profileActionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProfilesTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get autoDetectProcess => $composableBuilder(
    column: $table.autoDetectProcess,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> profileActionsRefs(
    Expression<bool> Function($$ProfileActionsTableFilterComposer f) f,
  ) {
    final $$ProfileActionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.profileActions,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfileActionsTableFilterComposer(
            $db: $db,
            $table: $db.profileActions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get autoDetectProcess => $composableBuilder(
    column: $table.autoDetectProcess,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<String> get autoDetectProcess => $composableBuilder(
    column: $table.autoDetectProcess,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> profileActionsRefs<T extends Object>(
    Expression<T> Function($$ProfileActionsTableAnnotationComposer a) f,
  ) {
    final $$ProfileActionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.profileActions,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfileActionsTableAnnotationComposer(
            $db: $db,
            $table: $db.profileActions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $ProfilesTable,
          Profile,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (Profile, $$ProfilesTableReferences),
          Profile,
          PrefetchHooks Function({bool profileActionsRefs})
        > {
  $$ProfilesTableTableManager(_$NexoDeckDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> colorHex = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<String?> autoDetectProcess = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion(
                id: id,
                name: name,
                icon: icon,
                colorHex: colorHex,
                isDefault: isDefault,
                autoDetectProcess: autoDetectProcess,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String name,
                Value<String> icon = const Value.absent(),
                Value<String> colorHex = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<String?> autoDetectProcess = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion.insert(
                id: id,
                name: name,
                icon: icon,
                colorHex: colorHex,
                isDefault: isDefault,
                autoDetectProcess: autoDetectProcess,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProfilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileActionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (profileActionsRefs) db.profileActions,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (profileActionsRefs)
                    await $_getPrefetchedData<
                      Profile,
                      $ProfilesTable,
                      ProfileAction
                    >(
                      currentTable: table,
                      referencedTable: $$ProfilesTableReferences
                          ._profileActionsRefsTable(db),
                      managerFromTypedResult: (p0) => $$ProfilesTableReferences(
                        db,
                        table,
                        p0,
                      ).profileActionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.profileId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $ProfilesTable,
      Profile,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (Profile, $$ProfilesTableReferences),
      Profile,
      PrefetchHooks Function({bool profileActionsRefs})
    >;
typedef $$ProfileActionsTableCreateCompanionBuilder =
    ProfileActionsCompanion Function({
      required String profileId,
      required String actionId,
      Value<int> orderIndex,
      Value<int> rowid,
    });
typedef $$ProfileActionsTableUpdateCompanionBuilder =
    ProfileActionsCompanion Function({
      Value<String> profileId,
      Value<String> actionId,
      Value<int> orderIndex,
      Value<int> rowid,
    });

final class $$ProfileActionsTableReferences
    extends
        BaseReferences<
          _$NexoDeckDatabase,
          $ProfileActionsTable,
          ProfileAction
        > {
  $$ProfileActionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProfilesTable _profileIdTable(_$NexoDeckDatabase db) =>
      db.profiles.createAlias('profile_actions__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ActionsTableTable _actionIdTable(_$NexoDeckDatabase db) => db
      .actionsTable
      .createAlias('profile_actions__action_id__actions_table__id');

  $$ActionsTableTableProcessedTableManager get actionId {
    final $_column = $_itemColumn<String>('action_id')!;

    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_actionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProfileActionsTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $ProfileActionsTable> {
  $$ProfileActionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionsTableTableFilterComposer get actionId {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileActionsTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $ProfileActionsTable> {
  $$ProfileActionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionsTableTableOrderingComposer get actionId {
    final $$ActionsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableOrderingComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileActionsTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $ProfileActionsTable> {
  $$ProfileActionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionsTableTableAnnotationComposer get actionId {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileActionsTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $ProfileActionsTable,
          ProfileAction,
          $$ProfileActionsTableFilterComposer,
          $$ProfileActionsTableOrderingComposer,
          $$ProfileActionsTableAnnotationComposer,
          $$ProfileActionsTableCreateCompanionBuilder,
          $$ProfileActionsTableUpdateCompanionBuilder,
          (ProfileAction, $$ProfileActionsTableReferences),
          ProfileAction,
          PrefetchHooks Function({bool profileId, bool actionId})
        > {
  $$ProfileActionsTableTableManager(
    _$NexoDeckDatabase db,
    $ProfileActionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfileActionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfileActionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfileActionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> actionId = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfileActionsCompanion(
                profileId: profileId,
                actionId: actionId,
                orderIndex: orderIndex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String actionId,
                Value<int> orderIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfileActionsCompanion.insert(
                profileId: profileId,
                actionId: actionId,
                orderIndex: orderIndex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProfileActionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false, actionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.profileId,
                                referencedTable: $$ProfileActionsTableReferences
                                    ._profileIdTable(db),
                                referencedColumn:
                                    $$ProfileActionsTableReferences
                                        ._profileIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (actionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.actionId,
                                referencedTable: $$ProfileActionsTableReferences
                                    ._actionIdTable(db),
                                referencedColumn:
                                    $$ProfileActionsTableReferences
                                        ._actionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProfileActionsTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $ProfileActionsTable,
      ProfileAction,
      $$ProfileActionsTableFilterComposer,
      $$ProfileActionsTableOrderingComposer,
      $$ProfileActionsTableAnnotationComposer,
      $$ProfileActionsTableCreateCompanionBuilder,
      $$ProfileActionsTableUpdateCompanionBuilder,
      (ProfileAction, $$ProfileActionsTableReferences),
      ProfileAction,
      PrefetchHooks Function({bool profileId, bool actionId})
    >;
typedef $$DevicesTableCreateCompanionBuilder =
    DevicesCompanion Function({
      Value<String> id,
      required String name,
      required DevicePlatform platform,
      required String certFingerprint,
      Value<TransportType?> lastTransportUsed,
      Value<DateTime?> lastConnectedAt,
      Value<bool> isAuthorized,
      Value<DateTime> pairedAt,
      Value<String?> manualHost,
      Value<int?> manualPort,
      Value<String?> relayHost,
      Value<int?> relayPort,
      Value<String?> relayTokenHex,
      Value<int> rowid,
    });
typedef $$DevicesTableUpdateCompanionBuilder =
    DevicesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DevicePlatform> platform,
      Value<String> certFingerprint,
      Value<TransportType?> lastTransportUsed,
      Value<DateTime?> lastConnectedAt,
      Value<bool> isAuthorized,
      Value<DateTime> pairedAt,
      Value<String?> manualHost,
      Value<int?> manualPort,
      Value<String?> relayHost,
      Value<int?> relayPort,
      Value<String?> relayTokenHex,
      Value<int> rowid,
    });

class $$DevicesTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DevicePlatform, DevicePlatform, String>
  get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get certFingerprint => $composableBuilder(
    column: $table.certFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TransportType?, TransportType, String>
  get lastTransportUsed => $composableBuilder(
    column: $table.lastTransportUsed,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAuthorized => $composableBuilder(
    column: $table.isAuthorized,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manualHost => $composableBuilder(
    column: $table.manualHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get manualPort => $composableBuilder(
    column: $table.manualPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relayHost => $composableBuilder(
    column: $table.relayHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relayPort => $composableBuilder(
    column: $table.relayPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relayTokenHex => $composableBuilder(
    column: $table.relayTokenHex,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DevicesTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get certFingerprint => $composableBuilder(
    column: $table.certFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastTransportUsed => $composableBuilder(
    column: $table.lastTransportUsed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAuthorized => $composableBuilder(
    column: $table.isAuthorized,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manualHost => $composableBuilder(
    column: $table.manualHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get manualPort => $composableBuilder(
    column: $table.manualPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relayHost => $composableBuilder(
    column: $table.relayHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relayPort => $composableBuilder(
    column: $table.relayPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relayTokenHex => $composableBuilder(
    column: $table.relayTokenHex,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DevicePlatform, String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get certFingerprint => $composableBuilder(
    column: $table.certFingerprint,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TransportType?, String>
  get lastTransportUsed => $composableBuilder(
    column: $table.lastTransportUsed,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isAuthorized => $composableBuilder(
    column: $table.isAuthorized,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);

  GeneratedColumn<String> get manualHost => $composableBuilder(
    column: $table.manualHost,
    builder: (column) => column,
  );

  GeneratedColumn<int> get manualPort => $composableBuilder(
    column: $table.manualPort,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relayHost =>
      $composableBuilder(column: $table.relayHost, builder: (column) => column);

  GeneratedColumn<int> get relayPort =>
      $composableBuilder(column: $table.relayPort, builder: (column) => column);

  GeneratedColumn<String> get relayTokenHex => $composableBuilder(
    column: $table.relayTokenHex,
    builder: (column) => column,
  );
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $DevicesTable,
          Device,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (Device, BaseReferences<_$NexoDeckDatabase, $DevicesTable, Device>),
          Device,
          PrefetchHooks Function()
        > {
  $$DevicesTableTableManager(_$NexoDeckDatabase db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DevicePlatform> platform = const Value.absent(),
                Value<String> certFingerprint = const Value.absent(),
                Value<TransportType?> lastTransportUsed = const Value.absent(),
                Value<DateTime?> lastConnectedAt = const Value.absent(),
                Value<bool> isAuthorized = const Value.absent(),
                Value<DateTime> pairedAt = const Value.absent(),
                Value<String?> manualHost = const Value.absent(),
                Value<int?> manualPort = const Value.absent(),
                Value<String?> relayHost = const Value.absent(),
                Value<int?> relayPort = const Value.absent(),
                Value<String?> relayTokenHex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                id: id,
                name: name,
                platform: platform,
                certFingerprint: certFingerprint,
                lastTransportUsed: lastTransportUsed,
                lastConnectedAt: lastConnectedAt,
                isAuthorized: isAuthorized,
                pairedAt: pairedAt,
                manualHost: manualHost,
                manualPort: manualPort,
                relayHost: relayHost,
                relayPort: relayPort,
                relayTokenHex: relayTokenHex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String name,
                required DevicePlatform platform,
                required String certFingerprint,
                Value<TransportType?> lastTransportUsed = const Value.absent(),
                Value<DateTime?> lastConnectedAt = const Value.absent(),
                Value<bool> isAuthorized = const Value.absent(),
                Value<DateTime> pairedAt = const Value.absent(),
                Value<String?> manualHost = const Value.absent(),
                Value<int?> manualPort = const Value.absent(),
                Value<String?> relayHost = const Value.absent(),
                Value<int?> relayPort = const Value.absent(),
                Value<String?> relayTokenHex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                id: id,
                name: name,
                platform: platform,
                certFingerprint: certFingerprint,
                lastTransportUsed: lastTransportUsed,
                lastConnectedAt: lastConnectedAt,
                isAuthorized: isAuthorized,
                pairedAt: pairedAt,
                manualHost: manualHost,
                manualPort: manualPort,
                relayHost: relayHost,
                relayPort: relayPort,
                relayTokenHex: relayTokenHex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $DevicesTable,
      Device,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (Device, BaseReferences<_$NexoDeckDatabase, $DevicesTable, Device>),
      Device,
      PrefetchHooks Function()
    >;
typedef $$AlertRulesTableCreateCompanionBuilder =
    AlertRulesCompanion Function({
      Value<String> id,
      required AlertMetric metric,
      required AlertOperator operatorType,
      required double threshold,
      Value<bool> isEnabled,
      Value<NotifyTarget> notifyTarget,
      Value<int> cooldownSeconds,
      Value<int> rowid,
    });
typedef $$AlertRulesTableUpdateCompanionBuilder =
    AlertRulesCompanion Function({
      Value<String> id,
      Value<AlertMetric> metric,
      Value<AlertOperator> operatorType,
      Value<double> threshold,
      Value<bool> isEnabled,
      Value<NotifyTarget> notifyTarget,
      Value<int> cooldownSeconds,
      Value<int> rowid,
    });

class $$AlertRulesTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $AlertRulesTable> {
  $$AlertRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AlertMetric, AlertMetric, String> get metric =>
      $composableBuilder(
        column: $table.metric,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<AlertOperator, AlertOperator, String>
  get operatorType => $composableBuilder(
    column: $table.operatorType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<double> get threshold => $composableBuilder(
    column: $table.threshold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<NotifyTarget, NotifyTarget, String>
  get notifyTarget => $composableBuilder(
    column: $table.notifyTarget,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get cooldownSeconds => $composableBuilder(
    column: $table.cooldownSeconds,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlertRulesTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $AlertRulesTable> {
  $$AlertRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metric => $composableBuilder(
    column: $table.metric,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operatorType => $composableBuilder(
    column: $table.operatorType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get threshold => $composableBuilder(
    column: $table.threshold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notifyTarget => $composableBuilder(
    column: $table.notifyTarget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cooldownSeconds => $composableBuilder(
    column: $table.cooldownSeconds,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlertRulesTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $AlertRulesTable> {
  $$AlertRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AlertMetric, String> get metric =>
      $composableBuilder(column: $table.metric, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AlertOperator, String> get operatorType =>
      $composableBuilder(
        column: $table.operatorType,
        builder: (column) => column,
      );

  GeneratedColumn<double> get threshold =>
      $composableBuilder(column: $table.threshold, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumnWithTypeConverter<NotifyTarget, String> get notifyTarget =>
      $composableBuilder(
        column: $table.notifyTarget,
        builder: (column) => column,
      );

  GeneratedColumn<int> get cooldownSeconds => $composableBuilder(
    column: $table.cooldownSeconds,
    builder: (column) => column,
  );
}

class $$AlertRulesTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $AlertRulesTable,
          AlertRule,
          $$AlertRulesTableFilterComposer,
          $$AlertRulesTableOrderingComposer,
          $$AlertRulesTableAnnotationComposer,
          $$AlertRulesTableCreateCompanionBuilder,
          $$AlertRulesTableUpdateCompanionBuilder,
          (
            AlertRule,
            BaseReferences<_$NexoDeckDatabase, $AlertRulesTable, AlertRule>,
          ),
          AlertRule,
          PrefetchHooks Function()
        > {
  $$AlertRulesTableTableManager(_$NexoDeckDatabase db, $AlertRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlertRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlertRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlertRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<AlertMetric> metric = const Value.absent(),
                Value<AlertOperator> operatorType = const Value.absent(),
                Value<double> threshold = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                Value<NotifyTarget> notifyTarget = const Value.absent(),
                Value<int> cooldownSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlertRulesCompanion(
                id: id,
                metric: metric,
                operatorType: operatorType,
                threshold: threshold,
                isEnabled: isEnabled,
                notifyTarget: notifyTarget,
                cooldownSeconds: cooldownSeconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required AlertMetric metric,
                required AlertOperator operatorType,
                required double threshold,
                Value<bool> isEnabled = const Value.absent(),
                Value<NotifyTarget> notifyTarget = const Value.absent(),
                Value<int> cooldownSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlertRulesCompanion.insert(
                id: id,
                metric: metric,
                operatorType: operatorType,
                threshold: threshold,
                isEnabled: isEnabled,
                notifyTarget: notifyTarget,
                cooldownSeconds: cooldownSeconds,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlertRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $AlertRulesTable,
      AlertRule,
      $$AlertRulesTableFilterComposer,
      $$AlertRulesTableOrderingComposer,
      $$AlertRulesTableAnnotationComposer,
      $$AlertRulesTableCreateCompanionBuilder,
      $$AlertRulesTableUpdateCompanionBuilder,
      (
        AlertRule,
        BaseReferences<_$NexoDeckDatabase, $AlertRulesTable, AlertRule>,
      ),
      AlertRule,
      PrefetchHooks Function()
    >;
typedef $$HardwareHistoryTableCreateCompanionBuilder =
    HardwareHistoryCompanion Function({
      Value<int> id,
      Value<DateTime> timestamp,
      required double cpuUsage,
      Value<double?> cpuTemp,
      Value<double?> cpuFreqMhz,
      Value<double?> gpuUsage,
      Value<double?> gpuTemp,
      Value<double?> gpuVramUsedMb,
      required double ramUsedMb,
      required double ramTotalMb,
      Value<int?> diskReadBytesPerSec,
      Value<int?> diskWriteBytesPerSec,
      Value<int?> netRxBytesPerSec,
      Value<int?> netTxBytesPerSec,
    });
typedef $$HardwareHistoryTableUpdateCompanionBuilder =
    HardwareHistoryCompanion Function({
      Value<int> id,
      Value<DateTime> timestamp,
      Value<double> cpuUsage,
      Value<double?> cpuTemp,
      Value<double?> cpuFreqMhz,
      Value<double?> gpuUsage,
      Value<double?> gpuTemp,
      Value<double?> gpuVramUsedMb,
      Value<double> ramUsedMb,
      Value<double> ramTotalMb,
      Value<int?> diskReadBytesPerSec,
      Value<int?> diskWriteBytesPerSec,
      Value<int?> netRxBytesPerSec,
      Value<int?> netTxBytesPerSec,
    });

class $$HardwareHistoryTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $HardwareHistoryTable> {
  $$HardwareHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cpuUsage => $composableBuilder(
    column: $table.cpuUsage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cpuTemp => $composableBuilder(
    column: $table.cpuTemp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cpuFreqMhz => $composableBuilder(
    column: $table.cpuFreqMhz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gpuUsage => $composableBuilder(
    column: $table.gpuUsage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gpuTemp => $composableBuilder(
    column: $table.gpuTemp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gpuVramUsedMb => $composableBuilder(
    column: $table.gpuVramUsedMb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ramUsedMb => $composableBuilder(
    column: $table.ramUsedMb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ramTotalMb => $composableBuilder(
    column: $table.ramTotalMb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get diskReadBytesPerSec => $composableBuilder(
    column: $table.diskReadBytesPerSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get diskWriteBytesPerSec => $composableBuilder(
    column: $table.diskWriteBytesPerSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get netRxBytesPerSec => $composableBuilder(
    column: $table.netRxBytesPerSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get netTxBytesPerSec => $composableBuilder(
    column: $table.netTxBytesPerSec,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HardwareHistoryTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $HardwareHistoryTable> {
  $$HardwareHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cpuUsage => $composableBuilder(
    column: $table.cpuUsage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cpuTemp => $composableBuilder(
    column: $table.cpuTemp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cpuFreqMhz => $composableBuilder(
    column: $table.cpuFreqMhz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gpuUsage => $composableBuilder(
    column: $table.gpuUsage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gpuTemp => $composableBuilder(
    column: $table.gpuTemp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gpuVramUsedMb => $composableBuilder(
    column: $table.gpuVramUsedMb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ramUsedMb => $composableBuilder(
    column: $table.ramUsedMb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ramTotalMb => $composableBuilder(
    column: $table.ramTotalMb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get diskReadBytesPerSec => $composableBuilder(
    column: $table.diskReadBytesPerSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get diskWriteBytesPerSec => $composableBuilder(
    column: $table.diskWriteBytesPerSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get netRxBytesPerSec => $composableBuilder(
    column: $table.netRxBytesPerSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get netTxBytesPerSec => $composableBuilder(
    column: $table.netTxBytesPerSec,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HardwareHistoryTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $HardwareHistoryTable> {
  $$HardwareHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<double> get cpuUsage =>
      $composableBuilder(column: $table.cpuUsage, builder: (column) => column);

  GeneratedColumn<double> get cpuTemp =>
      $composableBuilder(column: $table.cpuTemp, builder: (column) => column);

  GeneratedColumn<double> get cpuFreqMhz => $composableBuilder(
    column: $table.cpuFreqMhz,
    builder: (column) => column,
  );

  GeneratedColumn<double> get gpuUsage =>
      $composableBuilder(column: $table.gpuUsage, builder: (column) => column);

  GeneratedColumn<double> get gpuTemp =>
      $composableBuilder(column: $table.gpuTemp, builder: (column) => column);

  GeneratedColumn<double> get gpuVramUsedMb => $composableBuilder(
    column: $table.gpuVramUsedMb,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ramUsedMb =>
      $composableBuilder(column: $table.ramUsedMb, builder: (column) => column);

  GeneratedColumn<double> get ramTotalMb => $composableBuilder(
    column: $table.ramTotalMb,
    builder: (column) => column,
  );

  GeneratedColumn<int> get diskReadBytesPerSec => $composableBuilder(
    column: $table.diskReadBytesPerSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get diskWriteBytesPerSec => $composableBuilder(
    column: $table.diskWriteBytesPerSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get netRxBytesPerSec => $composableBuilder(
    column: $table.netRxBytesPerSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get netTxBytesPerSec => $composableBuilder(
    column: $table.netTxBytesPerSec,
    builder: (column) => column,
  );
}

class $$HardwareHistoryTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $HardwareHistoryTable,
          HardwareHistoryData,
          $$HardwareHistoryTableFilterComposer,
          $$HardwareHistoryTableOrderingComposer,
          $$HardwareHistoryTableAnnotationComposer,
          $$HardwareHistoryTableCreateCompanionBuilder,
          $$HardwareHistoryTableUpdateCompanionBuilder,
          (
            HardwareHistoryData,
            BaseReferences<
              _$NexoDeckDatabase,
              $HardwareHistoryTable,
              HardwareHistoryData
            >,
          ),
          HardwareHistoryData,
          PrefetchHooks Function()
        > {
  $$HardwareHistoryTableTableManager(
    _$NexoDeckDatabase db,
    $HardwareHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HardwareHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HardwareHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HardwareHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<double> cpuUsage = const Value.absent(),
                Value<double?> cpuTemp = const Value.absent(),
                Value<double?> cpuFreqMhz = const Value.absent(),
                Value<double?> gpuUsage = const Value.absent(),
                Value<double?> gpuTemp = const Value.absent(),
                Value<double?> gpuVramUsedMb = const Value.absent(),
                Value<double> ramUsedMb = const Value.absent(),
                Value<double> ramTotalMb = const Value.absent(),
                Value<int?> diskReadBytesPerSec = const Value.absent(),
                Value<int?> diskWriteBytesPerSec = const Value.absent(),
                Value<int?> netRxBytesPerSec = const Value.absent(),
                Value<int?> netTxBytesPerSec = const Value.absent(),
              }) => HardwareHistoryCompanion(
                id: id,
                timestamp: timestamp,
                cpuUsage: cpuUsage,
                cpuTemp: cpuTemp,
                cpuFreqMhz: cpuFreqMhz,
                gpuUsage: gpuUsage,
                gpuTemp: gpuTemp,
                gpuVramUsedMb: gpuVramUsedMb,
                ramUsedMb: ramUsedMb,
                ramTotalMb: ramTotalMb,
                diskReadBytesPerSec: diskReadBytesPerSec,
                diskWriteBytesPerSec: diskWriteBytesPerSec,
                netRxBytesPerSec: netRxBytesPerSec,
                netTxBytesPerSec: netTxBytesPerSec,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                required double cpuUsage,
                Value<double?> cpuTemp = const Value.absent(),
                Value<double?> cpuFreqMhz = const Value.absent(),
                Value<double?> gpuUsage = const Value.absent(),
                Value<double?> gpuTemp = const Value.absent(),
                Value<double?> gpuVramUsedMb = const Value.absent(),
                required double ramUsedMb,
                required double ramTotalMb,
                Value<int?> diskReadBytesPerSec = const Value.absent(),
                Value<int?> diskWriteBytesPerSec = const Value.absent(),
                Value<int?> netRxBytesPerSec = const Value.absent(),
                Value<int?> netTxBytesPerSec = const Value.absent(),
              }) => HardwareHistoryCompanion.insert(
                id: id,
                timestamp: timestamp,
                cpuUsage: cpuUsage,
                cpuTemp: cpuTemp,
                cpuFreqMhz: cpuFreqMhz,
                gpuUsage: gpuUsage,
                gpuTemp: gpuTemp,
                gpuVramUsedMb: gpuVramUsedMb,
                ramUsedMb: ramUsedMb,
                ramTotalMb: ramTotalMb,
                diskReadBytesPerSec: diskReadBytesPerSec,
                diskWriteBytesPerSec: diskWriteBytesPerSec,
                netRxBytesPerSec: netRxBytesPerSec,
                netTxBytesPerSec: netTxBytesPerSec,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HardwareHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $HardwareHistoryTable,
      HardwareHistoryData,
      $$HardwareHistoryTableFilterComposer,
      $$HardwareHistoryTableOrderingComposer,
      $$HardwareHistoryTableAnnotationComposer,
      $$HardwareHistoryTableCreateCompanionBuilder,
      $$HardwareHistoryTableUpdateCompanionBuilder,
      (
        HardwareHistoryData,
        BaseReferences<
          _$NexoDeckDatabase,
          $HardwareHistoryTable,
          HardwareHistoryData
        >,
      ),
      HardwareHistoryData,
      PrefetchHooks Function()
    >;
typedef $$SecretsRefsTableCreateCompanionBuilder =
    SecretsRefsCompanion Function({
      required String keyName,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$SecretsRefsTableUpdateCompanionBuilder =
    SecretsRefsCompanion Function({
      Value<String> keyName,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$SecretsRefsTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $SecretsRefsTable> {
  $$SecretsRefsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyName => $composableBuilder(
    column: $table.keyName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SecretsRefsTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $SecretsRefsTable> {
  $$SecretsRefsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyName => $composableBuilder(
    column: $table.keyName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SecretsRefsTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $SecretsRefsTable> {
  $$SecretsRefsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyName =>
      $composableBuilder(column: $table.keyName, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SecretsRefsTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $SecretsRefsTable,
          SecretsRef,
          $$SecretsRefsTableFilterComposer,
          $$SecretsRefsTableOrderingComposer,
          $$SecretsRefsTableAnnotationComposer,
          $$SecretsRefsTableCreateCompanionBuilder,
          $$SecretsRefsTableUpdateCompanionBuilder,
          (
            SecretsRef,
            BaseReferences<_$NexoDeckDatabase, $SecretsRefsTable, SecretsRef>,
          ),
          SecretsRef,
          PrefetchHooks Function()
        > {
  $$SecretsRefsTableTableManager(_$NexoDeckDatabase db, $SecretsRefsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SecretsRefsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SecretsRefsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SecretsRefsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> keyName = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SecretsRefsCompanion(
                keyName: keyName,
                description: description,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyName,
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SecretsRefsCompanion.insert(
                keyName: keyName,
                description: description,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SecretsRefsTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $SecretsRefsTable,
      SecretsRef,
      $$SecretsRefsTableFilterComposer,
      $$SecretsRefsTableOrderingComposer,
      $$SecretsRefsTableAnnotationComposer,
      $$SecretsRefsTableCreateCompanionBuilder,
      $$SecretsRefsTableUpdateCompanionBuilder,
      (
        SecretsRef,
        BaseReferences<_$NexoDeckDatabase, $SecretsRefsTable, SecretsRef>,
      ),
      SecretsRef,
      PrefetchHooks Function()
    >;
typedef $$WindowLayoutsTableCreateCompanionBuilder =
    WindowLayoutsCompanion Function({
      Value<String> id,
      required WindowMode mode,
      required double posX,
      required double posY,
      required double width,
      required double height,
      Value<String?> monitorId,
      Value<bool> alwaysOnTop,
      Value<int> rowid,
    });
typedef $$WindowLayoutsTableUpdateCompanionBuilder =
    WindowLayoutsCompanion Function({
      Value<String> id,
      Value<WindowMode> mode,
      Value<double> posX,
      Value<double> posY,
      Value<double> width,
      Value<double> height,
      Value<String?> monitorId,
      Value<bool> alwaysOnTop,
      Value<int> rowid,
    });

class $$WindowLayoutsTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $WindowLayoutsTable> {
  $$WindowLayoutsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<WindowMode, WindowMode, String> get mode =>
      $composableBuilder(
        column: $table.mode,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<double> get posX => $composableBuilder(
    column: $table.posX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get posY => $composableBuilder(
    column: $table.posY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get monitorId => $composableBuilder(
    column: $table.monitorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get alwaysOnTop => $composableBuilder(
    column: $table.alwaysOnTop,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WindowLayoutsTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $WindowLayoutsTable> {
  $$WindowLayoutsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get posX => $composableBuilder(
    column: $table.posX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get posY => $composableBuilder(
    column: $table.posY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get monitorId => $composableBuilder(
    column: $table.monitorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get alwaysOnTop => $composableBuilder(
    column: $table.alwaysOnTop,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WindowLayoutsTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $WindowLayoutsTable> {
  $$WindowLayoutsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<WindowMode, String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<double> get posX =>
      $composableBuilder(column: $table.posX, builder: (column) => column);

  GeneratedColumn<double> get posY =>
      $composableBuilder(column: $table.posY, builder: (column) => column);

  GeneratedColumn<double> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<double> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get monitorId =>
      $composableBuilder(column: $table.monitorId, builder: (column) => column);

  GeneratedColumn<bool> get alwaysOnTop => $composableBuilder(
    column: $table.alwaysOnTop,
    builder: (column) => column,
  );
}

class $$WindowLayoutsTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $WindowLayoutsTable,
          WindowLayout,
          $$WindowLayoutsTableFilterComposer,
          $$WindowLayoutsTableOrderingComposer,
          $$WindowLayoutsTableAnnotationComposer,
          $$WindowLayoutsTableCreateCompanionBuilder,
          $$WindowLayoutsTableUpdateCompanionBuilder,
          (
            WindowLayout,
            BaseReferences<
              _$NexoDeckDatabase,
              $WindowLayoutsTable,
              WindowLayout
            >,
          ),
          WindowLayout,
          PrefetchHooks Function()
        > {
  $$WindowLayoutsTableTableManager(
    _$NexoDeckDatabase db,
    $WindowLayoutsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WindowLayoutsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WindowLayoutsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WindowLayoutsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<WindowMode> mode = const Value.absent(),
                Value<double> posX = const Value.absent(),
                Value<double> posY = const Value.absent(),
                Value<double> width = const Value.absent(),
                Value<double> height = const Value.absent(),
                Value<String?> monitorId = const Value.absent(),
                Value<bool> alwaysOnTop = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WindowLayoutsCompanion(
                id: id,
                mode: mode,
                posX: posX,
                posY: posY,
                width: width,
                height: height,
                monitorId: monitorId,
                alwaysOnTop: alwaysOnTop,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required WindowMode mode,
                required double posX,
                required double posY,
                required double width,
                required double height,
                Value<String?> monitorId = const Value.absent(),
                Value<bool> alwaysOnTop = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WindowLayoutsCompanion.insert(
                id: id,
                mode: mode,
                posX: posX,
                posY: posY,
                width: width,
                height: height,
                monitorId: monitorId,
                alwaysOnTop: alwaysOnTop,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WindowLayoutsTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $WindowLayoutsTable,
      WindowLayout,
      $$WindowLayoutsTableFilterComposer,
      $$WindowLayoutsTableOrderingComposer,
      $$WindowLayoutsTableAnnotationComposer,
      $$WindowLayoutsTableCreateCompanionBuilder,
      $$WindowLayoutsTableUpdateCompanionBuilder,
      (
        WindowLayout,
        BaseReferences<_$NexoDeckDatabase, $WindowLayoutsTable, WindowLayout>,
      ),
      WindowLayout,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$NexoDeckDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$NexoDeckDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$NexoDeckDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$HubSubscriptionsTableCreateCompanionBuilder =
    HubSubscriptionsCompanion Function({
      Value<String> id,
      required String name,
      required HubSubscriptionKind kind,
      required String baseUrl,
      Value<String?> hubPath,
      Value<String?> invokeMethod,
      Value<String?> invokeArgsJson,
      Value<bool> allowInvalidCert,
      Value<HubSubscriptionStatus> status,
      Value<DateTime> createdAt,
      Value<DateTime?> lastEventAt,
      Value<String?> lastEventSummary,
      Value<int> rowid,
    });
typedef $$HubSubscriptionsTableUpdateCompanionBuilder =
    HubSubscriptionsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<HubSubscriptionKind> kind,
      Value<String> baseUrl,
      Value<String?> hubPath,
      Value<String?> invokeMethod,
      Value<String?> invokeArgsJson,
      Value<bool> allowInvalidCert,
      Value<HubSubscriptionStatus> status,
      Value<DateTime> createdAt,
      Value<DateTime?> lastEventAt,
      Value<String?> lastEventSummary,
      Value<int> rowid,
    });

final class $$HubSubscriptionsTableReferences
    extends
        BaseReferences<
          _$NexoDeckDatabase,
          $HubSubscriptionsTable,
          HubSubscription
        > {
  $$HubSubscriptionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$HubMessagesTable, List<HubMessage>>
  _hubMessagesRefsTable(_$NexoDeckDatabase db) => MultiTypedResultKey.fromTable(
    db.hubMessages,
    aliasName: 'hub_subscriptions__id__hub_messages__subscription_id',
  );

  $$HubMessagesTableProcessedTableManager get hubMessagesRefs {
    final manager = $$HubMessagesTableTableManager(
      $_db,
      $_db.hubMessages,
    ).filter((f) => f.subscriptionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_hubMessagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$HubSubscriptionsTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $HubSubscriptionsTable> {
  $$HubSubscriptionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    HubSubscriptionKind,
    HubSubscriptionKind,
    String
  >
  get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hubPath => $composableBuilder(
    column: $table.hubPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invokeMethod => $composableBuilder(
    column: $table.invokeMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invokeArgsJson => $composableBuilder(
    column: $table.invokeArgsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowInvalidCert => $composableBuilder(
    column: $table.allowInvalidCert,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    HubSubscriptionStatus,
    HubSubscriptionStatus,
    String
  >
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastEventAt => $composableBuilder(
    column: $table.lastEventAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastEventSummary => $composableBuilder(
    column: $table.lastEventSummary,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> hubMessagesRefs(
    Expression<bool> Function($$HubMessagesTableFilterComposer f) f,
  ) {
    final $$HubMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hubMessages,
      getReferencedColumn: (t) => t.subscriptionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HubMessagesTableFilterComposer(
            $db: $db,
            $table: $db.hubMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HubSubscriptionsTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $HubSubscriptionsTable> {
  $$HubSubscriptionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hubPath => $composableBuilder(
    column: $table.hubPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invokeMethod => $composableBuilder(
    column: $table.invokeMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invokeArgsJson => $composableBuilder(
    column: $table.invokeArgsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowInvalidCert => $composableBuilder(
    column: $table.allowInvalidCert,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastEventAt => $composableBuilder(
    column: $table.lastEventAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastEventSummary => $composableBuilder(
    column: $table.lastEventSummary,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HubSubscriptionsTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $HubSubscriptionsTable> {
  $$HubSubscriptionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<HubSubscriptionKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get hubPath =>
      $composableBuilder(column: $table.hubPath, builder: (column) => column);

  GeneratedColumn<String> get invokeMethod => $composableBuilder(
    column: $table.invokeMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get invokeArgsJson => $composableBuilder(
    column: $table.invokeArgsJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allowInvalidCert => $composableBuilder(
    column: $table.allowInvalidCert,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<HubSubscriptionStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastEventAt => $composableBuilder(
    column: $table.lastEventAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastEventSummary => $composableBuilder(
    column: $table.lastEventSummary,
    builder: (column) => column,
  );

  Expression<T> hubMessagesRefs<T extends Object>(
    Expression<T> Function($$HubMessagesTableAnnotationComposer a) f,
  ) {
    final $$HubMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hubMessages,
      getReferencedColumn: (t) => t.subscriptionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HubMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.hubMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HubSubscriptionsTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $HubSubscriptionsTable,
          HubSubscription,
          $$HubSubscriptionsTableFilterComposer,
          $$HubSubscriptionsTableOrderingComposer,
          $$HubSubscriptionsTableAnnotationComposer,
          $$HubSubscriptionsTableCreateCompanionBuilder,
          $$HubSubscriptionsTableUpdateCompanionBuilder,
          (HubSubscription, $$HubSubscriptionsTableReferences),
          HubSubscription,
          PrefetchHooks Function({bool hubMessagesRefs})
        > {
  $$HubSubscriptionsTableTableManager(
    _$NexoDeckDatabase db,
    $HubSubscriptionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HubSubscriptionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HubSubscriptionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HubSubscriptionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<HubSubscriptionKind> kind = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<String?> hubPath = const Value.absent(),
                Value<String?> invokeMethod = const Value.absent(),
                Value<String?> invokeArgsJson = const Value.absent(),
                Value<bool> allowInvalidCert = const Value.absent(),
                Value<HubSubscriptionStatus> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastEventAt = const Value.absent(),
                Value<String?> lastEventSummary = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HubSubscriptionsCompanion(
                id: id,
                name: name,
                kind: kind,
                baseUrl: baseUrl,
                hubPath: hubPath,
                invokeMethod: invokeMethod,
                invokeArgsJson: invokeArgsJson,
                allowInvalidCert: allowInvalidCert,
                status: status,
                createdAt: createdAt,
                lastEventAt: lastEventAt,
                lastEventSummary: lastEventSummary,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String name,
                required HubSubscriptionKind kind,
                required String baseUrl,
                Value<String?> hubPath = const Value.absent(),
                Value<String?> invokeMethod = const Value.absent(),
                Value<String?> invokeArgsJson = const Value.absent(),
                Value<bool> allowInvalidCert = const Value.absent(),
                Value<HubSubscriptionStatus> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastEventAt = const Value.absent(),
                Value<String?> lastEventSummary = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HubSubscriptionsCompanion.insert(
                id: id,
                name: name,
                kind: kind,
                baseUrl: baseUrl,
                hubPath: hubPath,
                invokeMethod: invokeMethod,
                invokeArgsJson: invokeArgsJson,
                allowInvalidCert: allowInvalidCert,
                status: status,
                createdAt: createdAt,
                lastEventAt: lastEventAt,
                lastEventSummary: lastEventSummary,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$HubSubscriptionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({hubMessagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (hubMessagesRefs) db.hubMessages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (hubMessagesRefs)
                    await $_getPrefetchedData<
                      HubSubscription,
                      $HubSubscriptionsTable,
                      HubMessage
                    >(
                      currentTable: table,
                      referencedTable: $$HubSubscriptionsTableReferences
                          ._hubMessagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$HubSubscriptionsTableReferences(
                            db,
                            table,
                            p0,
                          ).hubMessagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.subscriptionId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$HubSubscriptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $HubSubscriptionsTable,
      HubSubscription,
      $$HubSubscriptionsTableFilterComposer,
      $$HubSubscriptionsTableOrderingComposer,
      $$HubSubscriptionsTableAnnotationComposer,
      $$HubSubscriptionsTableCreateCompanionBuilder,
      $$HubSubscriptionsTableUpdateCompanionBuilder,
      (HubSubscription, $$HubSubscriptionsTableReferences),
      HubSubscription,
      PrefetchHooks Function({bool hubMessagesRefs})
    >;
typedef $$HubMessagesTableCreateCompanionBuilder =
    HubMessagesCompanion Function({
      Value<int> id,
      required String subscriptionId,
      required String eventName,
      required String payloadJson,
      Value<DateTime> receivedAt,
    });
typedef $$HubMessagesTableUpdateCompanionBuilder =
    HubMessagesCompanion Function({
      Value<int> id,
      Value<String> subscriptionId,
      Value<String> eventName,
      Value<String> payloadJson,
      Value<DateTime> receivedAt,
    });

final class $$HubMessagesTableReferences
    extends BaseReferences<_$NexoDeckDatabase, $HubMessagesTable, HubMessage> {
  $$HubMessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $HubSubscriptionsTable _subscriptionIdTable(_$NexoDeckDatabase db) =>
      db.hubSubscriptions.createAlias(
        'hub_messages__subscription_id__hub_subscriptions__id',
      );

  $$HubSubscriptionsTableProcessedTableManager get subscriptionId {
    final $_column = $_itemColumn<String>('subscription_id')!;

    final manager = $$HubSubscriptionsTableTableManager(
      $_db,
      $_db.hubSubscriptions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_subscriptionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$HubMessagesTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $HubMessagesTable> {
  $$HubMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventName => $composableBuilder(
    column: $table.eventName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$HubSubscriptionsTableFilterComposer get subscriptionId {
    final $$HubSubscriptionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subscriptionId,
      referencedTable: $db.hubSubscriptions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HubSubscriptionsTableFilterComposer(
            $db: $db,
            $table: $db.hubSubscriptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HubMessagesTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $HubMessagesTable> {
  $$HubMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventName => $composableBuilder(
    column: $table.eventName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$HubSubscriptionsTableOrderingComposer get subscriptionId {
    final $$HubSubscriptionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subscriptionId,
      referencedTable: $db.hubSubscriptions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HubSubscriptionsTableOrderingComposer(
            $db: $db,
            $table: $db.hubSubscriptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HubMessagesTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $HubMessagesTable> {
  $$HubMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventName =>
      $composableBuilder(column: $table.eventName, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );

  $$HubSubscriptionsTableAnnotationComposer get subscriptionId {
    final $$HubSubscriptionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subscriptionId,
      referencedTable: $db.hubSubscriptions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HubSubscriptionsTableAnnotationComposer(
            $db: $db,
            $table: $db.hubSubscriptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HubMessagesTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $HubMessagesTable,
          HubMessage,
          $$HubMessagesTableFilterComposer,
          $$HubMessagesTableOrderingComposer,
          $$HubMessagesTableAnnotationComposer,
          $$HubMessagesTableCreateCompanionBuilder,
          $$HubMessagesTableUpdateCompanionBuilder,
          (HubMessage, $$HubMessagesTableReferences),
          HubMessage,
          PrefetchHooks Function({bool subscriptionId})
        > {
  $$HubMessagesTableTableManager(_$NexoDeckDatabase db, $HubMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HubMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HubMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HubMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> subscriptionId = const Value.absent(),
                Value<String> eventName = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
              }) => HubMessagesCompanion(
                id: id,
                subscriptionId: subscriptionId,
                eventName: eventName,
                payloadJson: payloadJson,
                receivedAt: receivedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String subscriptionId,
                required String eventName,
                required String payloadJson,
                Value<DateTime> receivedAt = const Value.absent(),
              }) => HubMessagesCompanion.insert(
                id: id,
                subscriptionId: subscriptionId,
                eventName: eventName,
                payloadJson: payloadJson,
                receivedAt: receivedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$HubMessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({subscriptionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (subscriptionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.subscriptionId,
                                referencedTable: $$HubMessagesTableReferences
                                    ._subscriptionIdTable(db),
                                referencedColumn: $$HubMessagesTableReferences
                                    ._subscriptionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$HubMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $HubMessagesTable,
      HubMessage,
      $$HubMessagesTableFilterComposer,
      $$HubMessagesTableOrderingComposer,
      $$HubMessagesTableAnnotationComposer,
      $$HubMessagesTableCreateCompanionBuilder,
      $$HubMessagesTableUpdateCompanionBuilder,
      (HubMessage, $$HubMessagesTableReferences),
      HubMessage,
      PrefetchHooks Function({bool subscriptionId})
    >;
typedef $$ChatConversationsTableCreateCompanionBuilder =
    ChatConversationsCompanion Function({
      Value<String> id,
      required String title,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> keepForever,
      Value<DateTime?> archivedAt,
      Value<int> rowid,
    });
typedef $$ChatConversationsTableUpdateCompanionBuilder =
    ChatConversationsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> keepForever,
      Value<DateTime?> archivedAt,
      Value<int> rowid,
    });

final class $$ChatConversationsTableReferences
    extends
        BaseReferences<
          _$NexoDeckDatabase,
          $ChatConversationsTable,
          ChatConversation
        > {
  $$ChatConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ChatMessagesTable, List<ChatMessage>>
  _chatMessagesRefsTable(_$NexoDeckDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.chatMessages,
        aliasName: 'chat_conversations__id__chat_messages__conversation_id',
      );

  $$ChatMessagesTableProcessedTableManager get chatMessagesRefs {
    final manager = $$ChatMessagesTableTableManager(
      $_db,
      $_db.chatMessages,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_chatMessagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChatConversationsTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $ChatConversationsTable> {
  $$ChatConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get keepForever => $composableBuilder(
    column: $table.keepForever,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> chatMessagesRefs(
    Expression<bool> Function($$ChatMessagesTableFilterComposer f) f,
  ) {
    final $$ChatMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chatMessages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatMessagesTableFilterComposer(
            $db: $db,
            $table: $db.chatMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatConversationsTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $ChatConversationsTable> {
  $$ChatConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get keepForever => $composableBuilder(
    column: $table.keepForever,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatConversationsTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $ChatConversationsTable> {
  $$ChatConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get keepForever => $composableBuilder(
    column: $table.keepForever,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  Expression<T> chatMessagesRefs<T extends Object>(
    Expression<T> Function($$ChatMessagesTableAnnotationComposer a) f,
  ) {
    final $$ChatMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chatMessages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.chatMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatConversationsTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $ChatConversationsTable,
          ChatConversation,
          $$ChatConversationsTableFilterComposer,
          $$ChatConversationsTableOrderingComposer,
          $$ChatConversationsTableAnnotationComposer,
          $$ChatConversationsTableCreateCompanionBuilder,
          $$ChatConversationsTableUpdateCompanionBuilder,
          (ChatConversation, $$ChatConversationsTableReferences),
          ChatConversation,
          PrefetchHooks Function({bool chatMessagesRefs})
        > {
  $$ChatConversationsTableTableManager(
    _$NexoDeckDatabase db,
    $ChatConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatConversationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> keepForever = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatConversationsCompanion(
                id: id,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                keepForever: keepForever,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String title,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> keepForever = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatConversationsCompanion.insert(
                id: id,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                keepForever: keepForever,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChatConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({chatMessagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (chatMessagesRefs) db.chatMessages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (chatMessagesRefs)
                    await $_getPrefetchedData<
                      ChatConversation,
                      $ChatConversationsTable,
                      ChatMessage
                    >(
                      currentTable: table,
                      referencedTable: $$ChatConversationsTableReferences
                          ._chatMessagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ChatConversationsTableReferences(
                            db,
                            table,
                            p0,
                          ).chatMessagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.conversationId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ChatConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $ChatConversationsTable,
      ChatConversation,
      $$ChatConversationsTableFilterComposer,
      $$ChatConversationsTableOrderingComposer,
      $$ChatConversationsTableAnnotationComposer,
      $$ChatConversationsTableCreateCompanionBuilder,
      $$ChatConversationsTableUpdateCompanionBuilder,
      (ChatConversation, $$ChatConversationsTableReferences),
      ChatConversation,
      PrefetchHooks Function({bool chatMessagesRefs})
    >;
typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<String> id,
      required String conversationId,
      required ChatMessageKind kind,
      required String content,
      Value<ChatMessageOrigin> origin,
      Value<String?> payload,
      required int position,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<ChatMessageKind> kind,
      Value<String> content,
      Value<ChatMessageOrigin> origin,
      Value<String?> payload,
      Value<int> position,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ChatMessagesTableReferences
    extends
        BaseReferences<_$NexoDeckDatabase, $ChatMessagesTable, ChatMessage> {
  $$ChatMessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChatConversationsTable _conversationIdTable(_$NexoDeckDatabase db) =>
      db.chatConversations.createAlias(
        'chat_messages__conversation_id__chat_conversations__id',
      );

  $$ChatConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$ChatConversationsTableTableManager(
      $_db,
      $_db.chatConversations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChatMessagesTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ChatMessageKind, ChatMessageKind, String>
  get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ChatMessageOrigin, ChatMessageOrigin, String>
  get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ChatConversationsTableFilterComposer get conversationId {
    final $$ChatConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.chatConversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatConversationsTableFilterComposer(
            $db: $db,
            $table: $db.chatConversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChatConversationsTableOrderingComposer get conversationId {
    final $$ChatConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.chatConversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.chatConversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ChatMessageKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ChatMessageOrigin, String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ChatConversationsTableAnnotationComposer get conversationId {
    final $$ChatConversationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.conversationId,
          referencedTable: $db.chatConversations,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ChatConversationsTableAnnotationComposer(
                $db: $db,
                $table: $db.chatConversations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $ChatMessagesTable,
          ChatMessage,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (ChatMessage, $$ChatMessagesTableReferences),
          ChatMessage,
          PrefetchHooks Function({bool conversationId})
        > {
  $$ChatMessagesTableTableManager(
    _$NexoDeckDatabase db,
    $ChatMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<ChatMessageKind> kind = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<ChatMessageOrigin> origin = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion(
                id: id,
                conversationId: conversationId,
                kind: kind,
                content: content,
                origin: origin,
                payload: payload,
                position: position,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String conversationId,
                required ChatMessageKind kind,
                required String content,
                Value<ChatMessageOrigin> origin = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                required int position,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                kind: kind,
                content: content,
                origin: origin,
                payload: payload,
                position: position,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChatMessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.conversationId,
                                referencedTable: $$ChatMessagesTableReferences
                                    ._conversationIdTable(db),
                                referencedColumn: $$ChatMessagesTableReferences
                                    ._conversationIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $ChatMessagesTable,
      ChatMessage,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (ChatMessage, $$ChatMessagesTableReferences),
      ChatMessage,
      PrefetchHooks Function({bool conversationId})
    >;
typedef $$NoteMirrorTableCreateCompanionBuilder =
    NoteMirrorCompanion Function({
      required String path,
      required String content,
      Value<String> baseHash,
      Value<String> localHash,
      Value<bool> private,
      Value<int?> modifiedSecs,
      Value<DateTime> updatedAt,
      Value<String?> conflictContent,
      Value<String?> conflictHash,
      Value<int> rowid,
    });
typedef $$NoteMirrorTableUpdateCompanionBuilder =
    NoteMirrorCompanion Function({
      Value<String> path,
      Value<String> content,
      Value<String> baseHash,
      Value<String> localHash,
      Value<bool> private,
      Value<int?> modifiedSecs,
      Value<DateTime> updatedAt,
      Value<String?> conflictContent,
      Value<String?> conflictHash,
      Value<int> rowid,
    });

class $$NoteMirrorTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $NoteMirrorTable> {
  $$NoteMirrorTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseHash => $composableBuilder(
    column: $table.baseHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localHash => $composableBuilder(
    column: $table.localHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get private => $composableBuilder(
    column: $table.private,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedSecs => $composableBuilder(
    column: $table.modifiedSecs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictContent => $composableBuilder(
    column: $table.conflictContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictHash => $composableBuilder(
    column: $table.conflictHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteMirrorTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $NoteMirrorTable> {
  $$NoteMirrorTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseHash => $composableBuilder(
    column: $table.baseHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localHash => $composableBuilder(
    column: $table.localHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get private => $composableBuilder(
    column: $table.private,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedSecs => $composableBuilder(
    column: $table.modifiedSecs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictContent => $composableBuilder(
    column: $table.conflictContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictHash => $composableBuilder(
    column: $table.conflictHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteMirrorTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $NoteMirrorTable> {
  $$NoteMirrorTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get baseHash =>
      $composableBuilder(column: $table.baseHash, builder: (column) => column);

  GeneratedColumn<String> get localHash =>
      $composableBuilder(column: $table.localHash, builder: (column) => column);

  GeneratedColumn<bool> get private =>
      $composableBuilder(column: $table.private, builder: (column) => column);

  GeneratedColumn<int> get modifiedSecs => $composableBuilder(
    column: $table.modifiedSecs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get conflictContent => $composableBuilder(
    column: $table.conflictContent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conflictHash => $composableBuilder(
    column: $table.conflictHash,
    builder: (column) => column,
  );
}

class $$NoteMirrorTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $NoteMirrorTable,
          NoteMirrorData,
          $$NoteMirrorTableFilterComposer,
          $$NoteMirrorTableOrderingComposer,
          $$NoteMirrorTableAnnotationComposer,
          $$NoteMirrorTableCreateCompanionBuilder,
          $$NoteMirrorTableUpdateCompanionBuilder,
          (
            NoteMirrorData,
            BaseReferences<
              _$NexoDeckDatabase,
              $NoteMirrorTable,
              NoteMirrorData
            >,
          ),
          NoteMirrorData,
          PrefetchHooks Function()
        > {
  $$NoteMirrorTableTableManager(_$NexoDeckDatabase db, $NoteMirrorTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteMirrorTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteMirrorTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteMirrorTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> baseHash = const Value.absent(),
                Value<String> localHash = const Value.absent(),
                Value<bool> private = const Value.absent(),
                Value<int?> modifiedSecs = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> conflictContent = const Value.absent(),
                Value<String?> conflictHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteMirrorCompanion(
                path: path,
                content: content,
                baseHash: baseHash,
                localHash: localHash,
                private: private,
                modifiedSecs: modifiedSecs,
                updatedAt: updatedAt,
                conflictContent: conflictContent,
                conflictHash: conflictHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                required String content,
                Value<String> baseHash = const Value.absent(),
                Value<String> localHash = const Value.absent(),
                Value<bool> private = const Value.absent(),
                Value<int?> modifiedSecs = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> conflictContent = const Value.absent(),
                Value<String?> conflictHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteMirrorCompanion.insert(
                path: path,
                content: content,
                baseHash: baseHash,
                localHash: localHash,
                private: private,
                modifiedSecs: modifiedSecs,
                updatedAt: updatedAt,
                conflictContent: conflictContent,
                conflictHash: conflictHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteMirrorTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $NoteMirrorTable,
      NoteMirrorData,
      $$NoteMirrorTableFilterComposer,
      $$NoteMirrorTableOrderingComposer,
      $$NoteMirrorTableAnnotationComposer,
      $$NoteMirrorTableCreateCompanionBuilder,
      $$NoteMirrorTableUpdateCompanionBuilder,
      (
        NoteMirrorData,
        BaseReferences<_$NexoDeckDatabase, $NoteMirrorTable, NoteMirrorData>,
      ),
      NoteMirrorData,
      PrefetchHooks Function()
    >;
typedef $$NoteOutboxTableCreateCompanionBuilder =
    NoteOutboxCompanion Function({
      Value<String> id,
      required String path,
      required String kind,
      Value<String> content,
      Value<String> baseHash,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$NoteOutboxTableUpdateCompanionBuilder =
    NoteOutboxCompanion Function({
      Value<String> id,
      Value<String> path,
      Value<String> kind,
      Value<String> content,
      Value<String> baseHash,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$NoteOutboxTableFilterComposer
    extends Composer<_$NexoDeckDatabase, $NoteOutboxTable> {
  $$NoteOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseHash => $composableBuilder(
    column: $table.baseHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteOutboxTableOrderingComposer
    extends Composer<_$NexoDeckDatabase, $NoteOutboxTable> {
  $$NoteOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseHash => $composableBuilder(
    column: $table.baseHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteOutboxTableAnnotationComposer
    extends Composer<_$NexoDeckDatabase, $NoteOutboxTable> {
  $$NoteOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get baseHash =>
      $composableBuilder(column: $table.baseHash, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$NoteOutboxTableTableManager
    extends
        RootTableManager<
          _$NexoDeckDatabase,
          $NoteOutboxTable,
          NoteOutboxData,
          $$NoteOutboxTableFilterComposer,
          $$NoteOutboxTableOrderingComposer,
          $$NoteOutboxTableAnnotationComposer,
          $$NoteOutboxTableCreateCompanionBuilder,
          $$NoteOutboxTableUpdateCompanionBuilder,
          (
            NoteOutboxData,
            BaseReferences<
              _$NexoDeckDatabase,
              $NoteOutboxTable,
              NoteOutboxData
            >,
          ),
          NoteOutboxData,
          PrefetchHooks Function()
        > {
  $$NoteOutboxTableTableManager(_$NexoDeckDatabase db, $NoteOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> baseHash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteOutboxCompanion(
                id: id,
                path: path,
                kind: kind,
                content: content,
                baseHash: baseHash,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String path,
                required String kind,
                Value<String> content = const Value.absent(),
                Value<String> baseHash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteOutboxCompanion.insert(
                id: id,
                path: path,
                kind: kind,
                content: content,
                baseHash: baseHash,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$NexoDeckDatabase,
      $NoteOutboxTable,
      NoteOutboxData,
      $$NoteOutboxTableFilterComposer,
      $$NoteOutboxTableOrderingComposer,
      $$NoteOutboxTableAnnotationComposer,
      $$NoteOutboxTableCreateCompanionBuilder,
      $$NoteOutboxTableUpdateCompanionBuilder,
      (
        NoteOutboxData,
        BaseReferences<_$NexoDeckDatabase, $NoteOutboxTable, NoteOutboxData>,
      ),
      NoteOutboxData,
      PrefetchHooks Function()
    >;

class $NexoDeckDatabaseManager {
  final _$NexoDeckDatabase _db;
  $NexoDeckDatabaseManager(this._db);
  $$ActionGroupsTableTableManager get actionGroups =>
      $$ActionGroupsTableTableManager(_db, _db.actionGroups);
  $$ActionsTableTableTableManager get actionsTable =>
      $$ActionsTableTableTableManager(_db, _db.actionsTable);
  $$ActionParametersTableTableManager get actionParameters =>
      $$ActionParametersTableTableManager(_db, _db.actionParameters);
  $$MacroStepsTableTableManager get macroSteps =>
      $$MacroStepsTableTableManager(_db, _db.macroSteps);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$ProfileActionsTableTableManager get profileActions =>
      $$ProfileActionsTableTableManager(_db, _db.profileActions);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$AlertRulesTableTableManager get alertRules =>
      $$AlertRulesTableTableManager(_db, _db.alertRules);
  $$HardwareHistoryTableTableManager get hardwareHistory =>
      $$HardwareHistoryTableTableManager(_db, _db.hardwareHistory);
  $$SecretsRefsTableTableManager get secretsRefs =>
      $$SecretsRefsTableTableManager(_db, _db.secretsRefs);
  $$WindowLayoutsTableTableManager get windowLayouts =>
      $$WindowLayoutsTableTableManager(_db, _db.windowLayouts);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$HubSubscriptionsTableTableManager get hubSubscriptions =>
      $$HubSubscriptionsTableTableManager(_db, _db.hubSubscriptions);
  $$HubMessagesTableTableManager get hubMessages =>
      $$HubMessagesTableTableManager(_db, _db.hubMessages);
  $$ChatConversationsTableTableManager get chatConversations =>
      $$ChatConversationsTableTableManager(_db, _db.chatConversations);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$NoteMirrorTableTableManager get noteMirror =>
      $$NoteMirrorTableTableManager(_db, _db.noteMirror);
  $$NoteOutboxTableTableManager get noteOutbox =>
      $$NoteOutboxTableTableManager(_db, _db.noteOutbox);
}

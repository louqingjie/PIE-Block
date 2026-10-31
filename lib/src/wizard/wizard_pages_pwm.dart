part of '../wizard_screen.dart';

class _PwmPage extends ConsumerWidget {
  const _PwmPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c =
            ref.watch(appControllerProvider).document!.config as EngineerConfig,
        pwm = c.pwm,
        ctrl = ref.read(appControllerProvider.notifier);
    void update(PwmGroupConfig value) =>
        ctrl.updateConfig(c.copyWith(pwm: value));
    return _PageFrame(
      title: 'PWM 与引脚角色',
      subtitle: '同一 PWM 组共享频率。角色与频率不匹配时会在检查页给出提示。',
      child: Column(
        children: [
          _Section(
            title: '分组频率',
            children: [
              _AdaptiveRow(
                children: [
                  for (final item in [
                    ('PWMA · P60/P62/P64/P66', pwm.pwma, true),
                    ('PWMB · P74/P75/P76/P77', pwm.pwmb, false),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _FieldAnchor(
                          path: item.$3 ? 'pwm.pwma' : 'pwm.pwmb',
                          child: DropdownButtonFormField(
                            initialValue: item.$2,
                            decoration: _fieldDecoration(
                              ref,
                              item.$3 ? 'pwm.pwma' : 'pwm.pwmb',
                              item.$1,
                            ),
                            items: PwmFrequency.values
                                .map(
                                  (f) => DropdownMenuItem(
                                    value: f,
                                    child: Text(
                                      f == PwmFrequency.hz50
                                          ? '50 Hz · 舵机/摩擦轮'
                                          : '10000 Hz · 电机',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => update(
                              item.$3
                                  ? pwm.copyWith(pwma: v)
                                  : pwm.copyWith(pwmb: v),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('禁用蜂鸣器反馈'),
                value: pwm.buzzerDisabled,
                onChanged: (v) => update(pwm.copyWith(buzzerDisabled: v)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '引脚输出角色',
            children: [
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final pin in [...expansionPins, ...mainServoPins])
                      () {
                        final isServo =
                            mainServoPins.contains(pin) ||
                            pwm.pinRoles[pin] == PinRole.servo;
                        final isFriction =
                            (pin == 'P64' || pin == 'P66') &&
                            pwm.pinRoles[pin] == PinRole.friction;
                        final ccw = pwm.servoMaxLimits[pin];
                        final cw = pwm.servoMinLimits[pin] == null
                            ? null
                            : -pwm.servoMinLimits[pin]!;
                        final compact =
                            constraints.maxWidth < _compactBreakpoint;
                        // 舵机行放不下完整的一排时退回换行布局，避免限幅字段被挤压。
                        final stacked =
                            compact || (isServo && constraints.maxWidth < 700);
                        final rowWidth = stacked
                            ? constraints.maxWidth
                            : isServo
                            ? 700.0
                            : 280.0;
                        final roleWidth = stacked
                            ? rowWidth
                            : rowWidth -
                                  (isServo
                                      ? 404.0
                                      : isFriction
                                      ? 118.0
                                      : 0.0);
                        return SizedBox(
                          width: rowWidth,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: roleWidth,
                                child: _FieldAnchor(
                                  path: 'pwm.pin_roles.$pin',
                                  child: DropdownButtonFormField<PinRole>(
                                    key: ValueKey('pwm.pin_roles.$pin'),
                                    initialValue: mainServoPins.contains(pin)
                                        ? PinRole.servo
                                        : pwm.pinRoles[pin],
                                    decoration: _fieldDecoration(
                                      ref,
                                      'pwm.pin_roles.$pin',
                                      pin,
                                    ),
                                    items: _roleItems(pin, pwm.pinRoles[pin]),
                                    onChanged: mainServoPins.contains(pin)
                                        ? null
                                        : (v) {
                                            final roles = {
                                              ...pwm.pinRoles,
                                              pin: v!,
                                            };
                                            update(
                                              pwm.copyWith(pinRoles: roles),
                                            );
                                          },
                                  ),
                                ),
                              ),
                              if (isServo) ...[
                                SizedBox(
                                  width: 100,
                                  child: _NumberField(
                                    label: '中位°',
                                    fieldPath: 'pwm.servo_mids.$pin',
                                    value: pwm.servoMids[pin],
                                    onChanged: (v) {
                                      final mids = {...pwm.servoMids};
                                      if (v == null) {
                                        mids.remove(pin);
                                      } else {
                                        mids[pin] = v;
                                      }
                                      update(pwm.copyWith(servoMids: mids));
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: 140,
                                  child: _NumberField(
                                    label: '逆时针限幅°',
                                    fieldPath: 'pwm.servo_max_limits.$pin',
                                    value: ccw,
                                    onChanged: (v) {
                                      final limits = {
                                        ...pwm.servoMaxLimits,
                                      };
                                      if (v == null) {
                                        limits.remove(pin);
                                      } else {
                                        limits[pin] = v;
                                      }
                                      update(
                                        pwm.copyWith(servoMaxLimits: limits),
                                      );
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: 140,
                                  child: _NumberField(
                                    label: '顺时针限幅°',
                                    fieldPath: 'pwm.servo_min_limits.$pin',
                                    value: cw,
                                    onChanged: (v) {
                                      final limits = {
                                        ...pwm.servoMinLimits,
                                      };
                                      if (v == null) {
                                        limits.remove(pin);
                                      } else {
                                        limits[pin] = -v;
                                      }
                                      update(
                                        pwm.copyWith(servoMinLimits: limits),
                                      );
                                    },
                                  ),
                                ),
                              ],
                              if (isFriction)
                                SizedBox(
                                  width: 110,
                                  child: _NumberField(
                                    label: '满油 duty',
                                    fieldPath: 'pwm.friction_max_duties.$pin',
                                    value: pwm.frictionMaxDuties[pin],
                                    onChanged: (v) {
                                      final duties = {
                                        ...pwm.frictionMaxDuties,
                                      };
                                      if (v == null) {
                                        duties.remove(pin);
                                      } else {
                                        duties[pin] = v;
                                      }
                                      update(
                                        pwm.copyWith(
                                          frictionMaxDuties: duties,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        );
                      }(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _roleLabel(PinRole role) => switch (role) {
    PinRole.motor => '平滑电机',
    PinRole.servo => '舵机',
    PinRole.friction => '摩擦轮',
    PinRole.jitterMotor => '抖动电机',
    PinRole.unused => '未使用',
  };

  static List<DropdownMenuItem<PinRole>> _roleItems(
    String pin,
    PinRole? current,
  ) {
    final allowed = EngineerPinCapabilities.allowedRoles(pin);
    return [
      if (current != null && !allowed.contains(current))
        DropdownMenuItem(
          value: current,
          enabled: false,
          child: Text('${_roleLabel(current)}（当前配置，不支持）'),
        ),
      for (final role in allowed)
        DropdownMenuItem(value: role, child: Text(_roleLabel(role))),
    ];
  }
}

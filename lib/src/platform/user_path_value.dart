/// 一条用户环境变量值及其注册表类型（1 = REG_SZ，2 = REG_EXPAND_SZ）。
///
/// 类型要保留：用户 PATH 里常见 `%JAVA_HOME%\bin` 这样的变量引用，写回时若
/// 变成 REG_SZ 并展开，就等于把用户的环境改死了。
class UserPathValue {
  const UserPathValue(this.value, this.type);

  final String value;
  final int type;
}

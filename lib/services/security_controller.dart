class SecurityController {
  static final SecurityController _instance = SecurityController._internal();
  factory SecurityController() => _instance;
  SecurityController._internal();

  bool shouldLockOnLeave = true;

  void pauseLocking() => shouldLockOnLeave = false;
  void resumeLocking() => shouldLockOnLeave = true;
}

/// 예외 → 사용자 친화적 메시지 변환
String friendlyError(Object e) {
  final s = e.toString();
  if (_isNetwork(s)) return '네트워크 연결을 확인하고 다시 시도해주세요';
  if (_isAuth(s)) return '로그인 세션이 만료됐어요. 다시 로그인해주세요';
  return '오류가 발생했습니다. 잠시 후 다시 시도해주세요';
}

bool isNetworkError(Object e) => _isNetwork(e.toString());
bool isAuthError(Object e) => _isAuth(e.toString());

bool _isNetwork(String s) =>
    s.contains('SocketException') ||
    s.contains('Failed host lookup') ||
    s.contains('Network is unreachable') ||
    s.contains('Connection refused') ||
    s.contains('Connection reset') ||
    s.contains('AuthRetryableFetchException') ||
    s.contains('TimeoutException');

bool _isAuth(String s) =>
    s.contains('JWTExpired') ||
    s.contains('token is expired') ||
    s.contains('invalid claim') ||
    s.contains('not authenticated') ||
    s.contains('Invalid Refresh Token') ||
    s.contains('Refresh Token Not Found');

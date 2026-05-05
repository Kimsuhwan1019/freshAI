import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../config.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── 이메일 로그인 ──────────────────────────────────────────

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('오류: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 구글 소셜 로그인 ───────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: AppConfig.googleClientId,
      );

      // 기존 세션 클리어 후 로그인
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return; // 사용자가 취소

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('Google ID 토큰을 가져오지 못했습니다.\nGoogle Cloud Console에서 OAuth 설정을 확인해주세요.');
      }

      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
      // AuthGate가 자동으로 HomeScreen으로 이동
    } on AuthException catch (e) {
      if (mounted) _showError('Supabase 오류: ${e.message}');
    } catch (e) {
      if (mounted) _showError('구글 로그인 실패: $e');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg), backgroundColor: const Color(0xFFFF453A)),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.5),
                radius: 1.2,
                colors: [Color(0xFF1A2A14), Color(0xFF0D0D0D)],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 64),
                    _buildLogo(),
                    const SizedBox(height: 48),

                    // 이메일 필드
                    _buildLabel('이메일'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return '이메일을 입력해주세요';
                        if (!v.contains('@')) return '올바른 이메일 형식이 아닙니다';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    // 비밀번호 필드
                    _buildLabel('비밀번호'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return '비밀번호를 입력해주세요';
                        if (v.length < 6) return '비밀번호는 6자 이상이어야 합니다';
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    // 이메일 로그인 버튼
                    _buildEmailSignInButton(),
                    const SizedBox(height: 20),

                    // OR 구분선
                    _buildDivider(),
                    const SizedBox(height: 20),

                    // 구글 로그인 버튼
                    _buildGoogleSignInButton(),
                    const SizedBox(height: 24),

                    // 회원가입 링크
                    _buildSignupRow(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF76C442), Color(0xFF4A9A24)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF76C442).withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.kitchen, size: 44, color: Colors.white),
        ),
        const SizedBox(height: 20),
        const Text(
          'FreshAI',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '스마트 냉장고 식재료 관리',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.5),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF9A9A9A),
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildEmailSignInButton() {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: (_isLoading || _isGoogleLoading) ? null : _signIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF76C442),
          foregroundColor: Colors.black,
          disabledBackgroundColor:
              const Color(0xFF76C442).withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.black, strokeWidth: 2.5),
              )
            : const Text(
                '로그인',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3),
              ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(
            child: Divider(color: Color(0xFF2A2A2A), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '또는',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12),
          ),
        ),
        const Expanded(
            child: Divider(color: Color(0xFF2A2A2A), thickness: 1)),
      ],
    );
  }

  Widget _buildGoogleSignInButton() {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: (_isLoading || _isGoogleLoading) ? null : _signInWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1A1A1A),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: _isGoogleLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Color(0xFF4285F4), strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleGIcon(),
                  const SizedBox(width: 10),
                  const Text(
                    '구글로 로그인',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSignupRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '계정이 없으신가요?',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SignupScreen()),
          ),
          style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF76C442)),
          child: const Text(
            '회원가입',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  Google "G" 색상 아이콘
// ──────────────────────────────────────────────────────────────

class _GoogleGIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 파란색 원호 (상단)
    _drawArc(canvas, center, radius,
        -160 * (3.14159 / 180), 110 * (3.14159 / 180),
        const Color(0xFF4285F4), size.width * 0.15);

    // 빨간색 원호 (우측 하단)
    _drawArc(canvas, center, radius,
        -50 * (3.14159 / 180), 80 * (3.14159 / 180),
        const Color(0xFFEA4335), size.width * 0.15);

    // 노란색 원호 (하단)
    _drawArc(canvas, center, radius,
        30 * (3.14159 / 180), 90 * (3.14159 / 180),
        const Color(0xFFFBBC05), size.width * 0.15);

    // 초록색 원호 (좌측 하단)
    _drawArc(canvas, center, radius,
        120 * (3.14159 / 180), 80 * (3.14159 / 180),
        const Color(0xFF34A853), size.width * 0.15);

    // 흰색 안쪽 원 (도넛 효과)
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.55, innerPaint);

    // 파란색 "G" 수평 바
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx,
        center.dy - size.height * 0.12,
        size.width * 0.94,
        center.dy + size.height * 0.12,
      ),
      barPaint,
    );
  }

  void _drawArc(Canvas canvas, Offset center, double radius,
      double startAngle, double sweepAngle, Color color, double strokeWidth) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.75),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_GoogleGPainter oldDelegate) => false;
}

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'api_client.dart';
import 'database_service.dart';
import 'secure_storage_service.dart';
import 'server_config_service.dart';
import 'user_service.dart';

class AuthService {
  static const String defaultLocalEmail = 'local@flowspace.app';
  static const String defaultLocalPassword = 'flowspace123';

  /// Register a new user with email verification
  static Future<Map<String, dynamic>> registerWithVerification({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      print('FlowSpace: Starting registration with verification for $email...');

      final response = await ApiClient.post(
        '/auth/register-with-verification',
        body: {'name': name, 'email': email, 'password': password},
      );

      print('FlowSpace: Registration response: $response');

      return {
        'success': true,
        'message': response['message'] ?? 'Verification email sent',
        'userId': response['userId'],
      };
    } catch (e, stack) {
      print('FlowSpace: ERROR in registration: $e');
      print('FlowSpace: Stack trace: $stack');
      rethrow;
    }
  }

  /// Verify email with token from email link
  static Future<Map<String, dynamic>> verifyEmail(String token) async {
    try {
      print('FlowSpace: Verifying email with token...');

      final response = await ApiClient.get('/auth/verify-email?token=$token');

      print('FlowSpace: Email verification response: $response');

      return {
        'success': true,
        'message': response['message'] ?? 'Email verified successfully',
      };
    } catch (e, stack) {
      print('FlowSpace: ERROR in email verification: $e');
      print('FlowSpace: Stack trace: $stack');
      rethrow;
    }
  }

  /// Register a new user with the production server (instant, no verification)
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String workspaceName,
  }) async {
    if (!await ServerConfigService.instance.isServerMode()) {
      return _createLocalAccount(
        name: name,
        email: email,
        password: password,
        workspaceName: workspaceName,
      );
    }

    try {
      print('FlowSpace: Starting registration for $email via API...');

      // Call the real API endpoint
      final response = await ApiClient.post(
        '/auth/register',
        body: {
          'name': name,
          'email': email,
          'password': password,
          'workspaceName': workspaceName,
        },
      );

      print('FlowSpace: Registration API response: $response');

      // Extract data from API response
      // Response format: { token: string, user: { id, email, displayName } }
      final responseMap = Map<String, dynamic>.from(response as Map);

      // Get token from response
      final token = responseMap['token'] as String?;
      if (token != null) {
        ApiClient.setToken(token);
        await SecureStorageService.setJwtToken(token); // Persist JWT token
      }
      if (responseMap['sessionToken'] != null) {
        ApiClient.setSessionToken(responseMap['sessionToken'] as String);
      }

      // Get user object from response
      final userObj = responseMap['user'] as Map<String, dynamic>?;
      if (userObj == null) {
        throw Exception(
          'Registration failed: No user object in response. Response: $response',
        );
      }

      final userId = userObj['id'] as String?;
      if (userId == null) {
        throw Exception(
          'Registration failed: No user ID in response. User object: $userObj',
        );
      }

      // Store user ID in secure storage
      await SecureStorageService.setCurrentUserId(userId);

      // Cache user data locally for offline access
      final normalizedEmail = _normalizeEmail(email);
      await DatabaseService.insertUser({
        'id': userId,
        'name': userObj['displayName'] as String? ?? name,
        'email': _normalizeEmail(userObj['email'] as String? ?? email),
        'password_hash': _hashLocalPassword(normalizedEmail, password),
        'avatar_url': userObj['avatarUrl'] as String?,
        'status': 'online',
        'created_at':
            userObj['createdAt'] as String? ?? DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('FlowSpace: Registration complete! User ID: $userId');

      return {'success': true, 'user': userObj};
    } catch (e, stack) {
      print('FlowSpace: ERROR in registration: $e');
      print('FlowSpace: Stack trace: $stack');
      print('FlowSpace: Creating offline local account for $email...');
      return _createLocalAccount(
        name: name,
        email: email,
        password: password,
        workspaceName: workspaceName,
      );
    }
  }

  /// Login with email and password (with Remember Me support and refresh tokens)
  static Future<Map<String, dynamic>> loginWithRememberMe({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    if (!await ServerConfigService.instance.isServerMode()) {
      return _loginLocal(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );
    }

    try {
      print('FlowSpace: Starting login with remember me for $email...');

      final response = await ApiClient.post(
        '/auth/login-with-remember-me',
        body: {'email': email, 'password': password, 'rememberMe': rememberMe},
      );

      print('FlowSpace: Login API response received: $response');

      final responseMap = Map<String, dynamic>.from(response as Map);

      // Store access token
      final token = responseMap['token'] as String?;
      if (token != null) {
        ApiClient.setToken(token);
        await SecureStorageService.setJwtToken(token);
      }

      // Store refresh token if provided
      final refreshToken = responseMap['refreshToken'] as String?;
      if (refreshToken != null) {
        await SecureStorageService.setRefreshToken(refreshToken);
      }

      // Get user object
      final userObj = responseMap['user'] as Map<String, dynamic>?;
      if (userObj == null) {
        throw Exception('Login failed: No user object in response');
      }

      final userId = userObj['id'] as String?;
      if (userId == null) {
        throw Exception('Login failed: No user ID in response');
      }

      await SecureStorageService.setCurrentUserId(userId);

      // Cache user data locally
      final normalizedEmail = _normalizeEmail(email);
      await DatabaseService.insertUser({
        'id': userId,
        'name':
            userObj['displayName'] as String? ??
            userObj['name'] as String? ??
            'User',
        'email': _normalizeEmail(userObj['email'] as String? ?? email),
        'password_hash': _hashLocalPassword(normalizedEmail, password),
        'avatar_url': userObj['avatarUrl'] as String?,
        'status': 'online',
        'created_at':
            userObj['createdAt'] as String? ?? DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('FlowSpace: Login complete! User ID: $userId');

      return {'success': true, 'user': userObj};
    } catch (e, stack) {
      print('FlowSpace: ERROR in login: $e');
      print('FlowSpace: Stack trace: $stack');
      print('FlowSpace: Trying offline local login for $email...');
      return _loginLocal(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );
    }
  }

  /// Refresh access token using refresh token
  static Future<String?> refreshAccessToken() async {
    try {
      final refreshToken = await SecureStorageService.getRefreshToken();
      if (refreshToken == null) {
        print('FlowSpace: No refresh token available');
        return null;
      }

      print('FlowSpace: Refreshing access token...');

      final response = await ApiClient.post(
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      );

      final newToken = response['token'] as String?;
      if (newToken != null) {
        ApiClient.setToken(newToken);
        await SecureStorageService.setJwtToken(newToken);
        print('FlowSpace: Access token refreshed successfully');
      }

      return newToken;
    } catch (e) {
      print('FlowSpace: Failed to refresh token: $e');
      return null;
    }
  }

  /// Login with email and password (simple, no refresh token)
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    if (!await ServerConfigService.instance.isServerMode()) {
      return _loginLocal(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );
    }

    try {
      print('FlowSpace: Starting login for $email via API...');

      // Call the real API endpoint
      final response = await ApiClient.post(
        '/auth/login',
        body: {'email': email, 'password': password},
      );

      print('FlowSpace: Login API response received: $response');

      // Extract data from API response
      // Response format: { token: string, user: { id, email, displayName } }
      final responseMap = Map<String, dynamic>.from(response as Map);

      // Get token from response
      final token = responseMap['token'] as String?;
      if (token != null) {
        ApiClient.setToken(token);
        await SecureStorageService.setJwtToken(token); // Persist JWT token
      }
      if (responseMap['sessionToken'] != null) {
        ApiClient.setSessionToken(responseMap['sessionToken'] as String);
      }

      // Get user object from response
      final userObj = responseMap['user'] as Map<String, dynamic>?;
      if (userObj == null) {
        throw Exception(
          'Login failed: No user object in response. Response: $response',
        );
      }

      final userId = userObj['id'] as String?;
      if (userId == null) {
        throw Exception(
          'Login failed: No user ID in response. User object: $userObj',
        );
      }

      // Store user ID in secure storage
      await SecureStorageService.setCurrentUserId(userId);

      // Cache user data locally for offline access
      final normalizedEmail = _normalizeEmail(email);
      await DatabaseService.insertUser({
        'id': userId,
        'name':
            userObj['displayName'] as String? ??
            userObj['name'] as String? ??
            'User',
        'email': _normalizeEmail(userObj['email'] as String? ?? email),
        'password_hash': _hashLocalPassword(normalizedEmail, password),
        'avatar_url': userObj['avatarUrl'] as String?,
        'status': 'online',
        'created_at':
            userObj['createdAt'] as String? ?? DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('FlowSpace: Login complete! User ID: $userId');

      // Save credentials if remember me is enabled
      if (rememberMe) {
        await SecureStorageService.saveCredentials(email, password);
      } else {
        await SecureStorageService.clearCredentials();
      }

      return {'success': true, 'user': userObj};
    } on TimeoutException catch (e) {
      print('FlowSpace: Login timeout: $e');
      throw Exception(
        'Server is slow, please wait... The request took longer than 30 seconds. Please try again.',
      );
    } catch (e, stack) {
      print('FlowSpace: ERROR in login: $e');
      print('FlowSpace: Stack trace: $stack');
      print('FlowSpace: Trying offline local login for $email...');
      return _loginLocal(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );
    }
  }

  /// Get current user (checks local cache first, then API)
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    // Restore JWT token from secure storage if not in memory
    if (ApiClient.token == null) {
      final storedToken = await SecureStorageService.getJwtToken();
      if (storedToken != null && storedToken.isNotEmpty) {
        ApiClient.setToken(storedToken);
      }
    }

    // First check local database
    final localUser = await DatabaseService.getCurrentUser();
    if (localUser != null) {
      // Try to refresh from API if we have a token
      if (ApiClient.token != null && ApiClient.token!.isNotEmpty) {
        try {
          final apiUser = await UserService.getProfile();
          // Update local cache with fresh data
          await DatabaseService.insertUser({
            'id': apiUser['id'] as String,
            'name':
                apiUser['name'] as String? ??
                apiUser['displayName'] as String? ??
                'User',
            'email': _normalizeEmail(apiUser['email'] as String),
            'password_hash': localUser['password_hash'],
            'avatar_url': apiUser['avatarUrl'] as String?,
            'status': 'online',
            'created_at':
                apiUser['createdAt'] as String? ??
                DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
          return apiUser;
        } catch (e) {
          print(
            'FlowSpace: Could not refresh user from API, using local cache: $e',
          );
          return localUser;
        }
      }
      return localUser;
    }
    return null;
  }

  /// Get the current JWT token
  static Future<String?> getToken() async {
    return await SecureStorageService.getJwtToken();
  }

  /// Legacy method for getting auth token (alias for getToken)
  static Future<String?> getAuthToken() async {
    try {
      // Prefer secure storage token
      final token = await SecureStorageService.getJwtToken();
      if (token != null && token.isNotEmpty) {
        return token;
      }

      // Fallback to in-memory token if available
      if (ApiClient.token != null && ApiClient.token!.isNotEmpty) {
        return ApiClient.token;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Logout - clear tokens and local data
  static Future<void> logout({bool clearRememberMe = false}) async {
    try {
      // Try to revoke refresh token on server
      final refreshToken = await SecureStorageService.getRefreshToken();
      if (refreshToken != null) {
        try {
          await ApiClient.post(
            '/auth/logout',
            body: {'refreshToken': refreshToken},
          );
        } catch (e) {
          print('FlowSpace: Failed to revoke refresh token on server: $e');
        }
      }

      // Clear API tokens
      ApiClient.clearAuth();

      // Clear JWT and refresh tokens from secure storage
      await SecureStorageService.setJwtToken('');
      await SecureStorageService.clearRefreshToken();

      // Clear secure storage
      final userId = await SecureStorageService.getCurrentUserId();
      if (userId != null) {
        await SecureStorageService.deleteEncryptedMasterKey(userId);
      }
      await SecureStorageService.setCurrentUserId('');

      // Clear credentials if explicitly requested
      if (clearRememberMe) {
        await SecureStorageService.clearCredentials();
      }

      print('FlowSpace: Logout complete');
    } catch (e) {
      print('FlowSpace: Error during logout: $e');
    }
  }

  /// Ensure downloaded local-first builds have a known offline account.
  static Future<void> ensureDefaultLocalAccount() async {
    final existing = await DatabaseService.getUserByEmail(defaultLocalEmail);
    if (existing != null) return;

    await _createLocalAccount(
      name: 'Local Admin',
      email: defaultLocalEmail,
      password: defaultLocalPassword,
      workspaceName: 'FlowSpace Local',
      activateSession: false,
    );
  }

  /// Create and activate an account without contacting a remote server.
  static Future<Map<String, dynamic>> createLocalAccount({
    required String name,
    required String email,
    required String password,
    required String workspaceName,
  }) {
    return _createLocalAccount(
      name: name,
      email: email,
      password: password,
      workspaceName: workspaceName,
    );
  }

  /// Authenticate only against the local SQLite account store.
  static Future<Map<String, dynamic>> loginLocal({
    required String email,
    required String password,
    bool rememberMe = false,
  }) {
    return _loginLocal(
      email: email,
      password: password,
      rememberMe: rememberMe,
    );
  }

  static Future<Map<String, dynamic>> _createLocalAccount({
    required String name,
    required String email,
    required String password,
    required String workspaceName,
    bool activateSession = true,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final now = DateTime.now().toIso8601String();
    final accountKey = sha1.convert(utf8.encode(normalizedEmail)).toString();
    final userId = 'local_user_${accountKey.substring(0, 12)}';
    final teamId = 'local_team_${accountKey.substring(0, 12)}';
    final workspaceId = 'local_workspace_${accountKey.substring(0, 12)}';
    final displayName = name.trim().isNotEmpty ? name.trim() : 'Local User';
    final displayWorkspace = workspaceName.trim().isNotEmpty
        ? workspaceName.trim()
        : 'Local Workspace';

    final user = {
      'id': userId,
      'name': displayName,
      'email': normalizedEmail,
      'password_hash': _hashLocalPassword(normalizedEmail, password),
      'avatar_url': null,
      'status': 'online',
      'created_at': now,
      'updated_at': now,
    };

    await DatabaseService.insertUser(user);
    await DatabaseService.insertTeam({
      'id': teamId,
      'name': displayWorkspace,
      'owner_id': userId,
      'created_at': now,
      'updated_at': now,
    });
    await DatabaseService.insertWorkspace({
      'id': workspaceId,
      'team_id': teamId,
      'name': displayWorkspace,
      'slug': _slugify(displayWorkspace),
      'description': 'Offline local workspace',
      'workspace_type': 'company',
      'owner_id': userId,
      'created_at': now,
      'updated_at': now,
    });
    await DatabaseService.addWorkspaceMember({
      'workspace_id': workspaceId,
      'user_id': userId,
      'role': 'owner',
      'joined_at': now,
    });

    for (final channel in const [
      {'name': 'general', 'description': 'Company-wide updates and discussion'},
      {'name': 'projects', 'description': 'Project planning and delivery'},
      {
        'name': 'meetings',
        'description': 'Meeting notes, calls, and follow-ups',
      },
    ]) {
      await DatabaseService.insertChannel({
        'id': '${workspaceId}_${channel['name']}',
        'workspace_id': workspaceId,
        'name': channel['name'],
        'description': channel['description'],
        'is_private': 0,
        'created_at': now,
        'updated_at': now,
      });
    }

    if (activateSession) {
      await SecureStorageService.setCurrentUserId(userId);
      await SecureStorageService.setJwtToken('');
      await SecureStorageService.clearRefreshToken();
      ApiClient.clearAuth();
    }

    return {'success': true, 'offline': true, 'user': user};
  }

  static Future<Map<String, dynamic>> _loginLocal({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    var user = await DatabaseService.getUserByEmail(normalizedEmail);
    user ??= await DatabaseService.getUserByEmail(email.trim());

    if (user == null) {
      throw Exception(
        'No local account found for $normalizedEmail. Create a local account first.',
      );
    }

    final storedHash = user['password_hash'] as String?;
    if (!_verifyLocalPassword(normalizedEmail, password, storedHash)) {
      throw Exception('Invalid local email or password.');
    }

    final userId = user['id'] as String;
    await SecureStorageService.setCurrentUserId(userId);
    await SecureStorageService.setJwtToken('');
    await SecureStorageService.clearRefreshToken();
    ApiClient.clearAuth();

    if (rememberMe) {
      await SecureStorageService.saveCredentials(normalizedEmail, password);
    } else {
      await SecureStorageService.clearCredentials();
    }

    await DatabaseService.insertUser({
      ...user,
      'email': normalizedEmail,
      'status': 'online',
      'updated_at': DateTime.now().toIso8601String(),
    });

    return {
      'success': true,
      'offline': true,
      'user': {...user, 'email': normalizedEmail, 'displayName': user['name']},
    };
  }

  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  static String _hashLocalPassword(String normalizedEmail, String password) {
    final digest = sha256.convert(utf8.encode('$normalizedEmail:$password'));
    return 'local-v1:$digest';
  }

  static bool _verifyLocalPassword(
    String normalizedEmail,
    String password,
    String? storedHash,
  ) {
    if (storedHash == null || storedHash.isEmpty) return false;
    return storedHash == _hashLocalPassword(normalizedEmail, password);
  }

  static String _slugify(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isNotEmpty ? slug : 'local-workspace';
  }
}

import functools
import hashlib
from datetime import datetime, timedelta, timezone
import jwt
from flask import request, jsonify, current_app
from werkzeug.security import generate_password_hash, check_password_hash
from database import db
from models import User

def hash_password(password: str) -> str:
    """Hash password using Werkzeug security with SHA-256 fallback compatibility."""
    clean_pw = password.strip()
    return generate_password_hash(clean_pw)

def verify_password(stored_hash: str, provided_password: str) -> bool:
    """
    Verify password against stored hash.
    Supports Werkzeug hashed passwords as well as plain SHA-256 hex hashes
    from the Flutter client demo auth provider.
    """
    clean_pw = provided_password.strip()
    # Check werkzeug hash first
    try:
        if check_password_hash(stored_hash, clean_pw):
            return True
    except Exception:
        pass
    
    # Check SHA-256 hex digest (matching Flutter's AppAuthProvider._hashPassword)
    sha256_hash = hashlib.sha256(clean_pw.encode('utf-8')).hexdigest()
    if stored_hash == sha256_hash:
        return True
    
    return False

def generate_token(user: User) -> str:
    """Generate a JWT token for the authenticated user."""
    secret = current_app.config['JWT_SECRET']
    now = datetime.now(timezone.utc)
    expiration = now + timedelta(hours=current_app.config.get('JWT_EXPIRATION_HOURS', 72))
    payload = {
        'sub': user.id,
        'email': user.email,
        'role': user.role,
        'exp': expiration,
        'iat': now
    }
    return jwt.encode(payload, secret, algorithm='HS256')

def token_required(f):
    """Decorator to require a valid JWT token on endpoints."""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization', None)
        if not auth_header:
            return jsonify({'error': 'Authorization token is missing', 'code': 'AUTH_MISSING'}), 401

        parts = auth_header.split()
        if len(parts) != 2 or parts[0].lower() != 'bearer':
            return jsonify({'error': 'Invalid token header format. Use: Bearer <token>', 'code': 'AUTH_INVALID_HEADER'}), 401

        token = parts[1]
        try:
            payload = jwt.decode(token, current_app.config['JWT_SECRET'], algorithms=['HS256'])
            user_id = payload.get('sub')
            user = db.session.get(User, user_id)
            if not user:
                return jsonify({'error': 'User not found', 'code': 'USER_NOT_FOUND'}), 401
            if not user.is_active:
                return jsonify({'error': 'Account deactivated. Please contact support.', 'code': 'USER_DEACTIVATED'}), 403
            return f(current_user=user, *args, **kwargs)
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token has expired', 'code': 'TOKEN_EXPIRED'}), 401
        except jwt.InvalidTokenError as e:
            return jsonify({'error': f'Invalid token: {str(e)}', 'code': 'TOKEN_INVALID'}), 401

    return decorated

def role_required(*allowed_roles):
    """Decorator to restrict access to specified roles."""
    def decorator(f):
        @functools.wraps(f)
        def decorated(current_user, *args, **kwargs):
            if current_user.role not in allowed_roles:
                return jsonify({
                    'error': f'Access forbidden. Role {current_user.role} is not authorized for this resource.',
                    'code': 'FORBIDDEN'
                }), 403
            return f(current_user=current_user, *args, **kwargs)
        return decorated
    return decorator

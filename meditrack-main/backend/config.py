import os

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'medtrack-secret-key-medical-records-manager-2026')
    JWT_SECRET = os.getenv('JWT_SECRET', 'medtrack-jwt-secret-key-smart-reports')
    JWT_EXPIRATION_HOURS = int(os.getenv('JWT_EXPIRATION_HOURS', '72'))
    
    # MySQL Database URI (defaults to MySQL, can be overridden by environment variable)
    # Example MySQL: mysql+pymysql://root:password@localhost:3306/meditrack
    # Fallback to local SQLite when MySQL is not configured
    DEFAULT_SQLITE_URI = f"sqlite:///{os.path.join(BASE_DIR, 'meditrack.db')}"
    SQLALCHEMY_DATABASE_URI = os.getenv('DATABASE_URL', DEFAULT_SQLITE_URI)
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # Upload settings
    UPLOAD_FOLDER = os.getenv('UPLOAD_FOLDER', os.path.join(BASE_DIR, 'uploads', 'reports'))
    MAX_CONTENT_LENGTH = 5 * 1024 * 1024  # 5 MB maximum file upload size
    ALLOWED_EXTENSIONS = {'pdf', 'jpg', 'jpeg', 'png'}

class TestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    UPLOAD_FOLDER = os.path.join(BASE_DIR, 'uploads', 'test_reports')

import os
from flask import Flask, jsonify
from flask_cors import CORS
from config import Config
from database import db
from routes import auth_bp, report_bp, record_bp

def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    # Enable CORS for Flutter mobile, web, and desktop
    CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=True)

    # Initialize database
    db.init_app(app)

    # Ensure upload directory exists
    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

    # Register Blueprints
    app.register_blueprint(auth_bp)
    app.register_blueprint(report_bp)
    app.register_blueprint(record_bp)

    @app.route('/api/health', methods=['GET'])
    def health_check():
        return jsonify({
            'status': 'healthy',
            'service': 'MedTrack Smart Medical Reports API',
            'version': '1.0.0'
        }), 200

    @app.errorhandler(413)
    def file_too_large(error):
        return jsonify({
            'error': 'Uploaded file exceeds the maximum allowed limit (5 MB).',
            'code': 'FILE_TOO_LARGE'
        }), 413

    @app.errorhandler(404)
    def not_found(error):
        return jsonify({
            'error': 'Resource not found',
            'code': 'NOT_FOUND'
        }), 404

    @app.errorhandler(500)
    def internal_error(error):
        return jsonify({
            'error': 'Internal server error',
            'code': 'SERVER_ERROR'
        }), 500

    with app.app_context():
        db.create_all()

    return app

if __name__ == '__main__':
    app = create_app()
    port = int(os.getenv('PORT', 5000))
    host = os.getenv('HOST', '0.0.0.0')
    print(f"🚀 MedTrack Flask API starting on http://{host}:{port}")
    app.run(host=host, port=port, debug=True)

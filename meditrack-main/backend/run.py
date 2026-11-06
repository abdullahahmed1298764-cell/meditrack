import os
from app import create_app

app = create_app()

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    host = os.getenv('HOST', '0.0.0.0')
    print("=" * 60)
    print(" MedTrack - Smart Medical Report Management API")
    print(f" Running at: http://127.0.0.1:{port}")
    print(f" Database:   {app.config['SQLALCHEMY_DATABASE_URI']}")
    print(f" Uploads:    {app.config['UPLOAD_FOLDER']}")
    print("=" * 60)
    app.run(host=host, port=port, debug=True)

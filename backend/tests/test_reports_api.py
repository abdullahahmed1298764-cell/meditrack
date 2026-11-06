import io
import os
import shutil
import pytest
from app import create_app
from config import TestConfig
from database import db
from models import User, DoctorPatientAccess, MedicalRecord

@pytest.fixture
def app():
    app = create_app(TestConfig)
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()
        # Clean up test uploads directory
        if os.path.exists(app.config['UPLOAD_FOLDER']):
            shutil.rmtree(app.config['UPLOAD_FOLDER'], ignore_errors=True)

@pytest.fixture
def client(app):
    return app.test_client()

@pytest.fixture
def auth_headers(client):
    """Register and return auth headers for patient A, patient B, and a doctor."""
    # Register Patient A
    res_a = client.post('/api/auth/register', json={
        'name': 'Patient Alice',
        'email': 'alice@example.com',
        'password': 'Password123!',
        'role': 'Patient'
    })
    token_a = res_a.get_json()['token']
    user_a = res_a.get_json()['user']

    # Register Patient B
    res_b = client.post('/api/auth/register', json={
        'name': 'Patient Bob',
        'email': 'bob@example.com',
        'password': 'Password123!',
        'role': 'Patient'
    })
    token_b = res_b.get_json()['token']
    user_b = res_b.get_json()['user']

    # Register Doctor
    res_doc = client.post('/api/auth/register', json={
        'name': 'Dr. House',
        'email': 'house@example.com',
        'password': 'Password123!',
        'role': 'Doctor'
    })
    token_doc = res_doc.get_json()['token']
    user_doc = res_doc.get_json()['user']

    return {
        'alice': {'headers': {'Authorization': f'Bearer {token_a}'}, 'user': user_a},
        'bob': {'headers': {'Authorization': f'Bearer {token_b}'}, 'user': user_b},
        'doctor': {'headers': {'Authorization': f'Bearer {token_doc}'}, 'user': user_doc},
    }

# Test 1: Uploading a valid PDF report
def test_upload_pdf_report(client, auth_headers):
    alice = auth_headers['alice']
    pdf_content = b"%PDF-1.4 sample pdf content for medical report testing"
    data = {
        'file': (io.BytesIO(pdf_content), 'blood_test_cbc.pdf'),
        'report_title': 'Complete Blood Count (CBC)',
        'report_category': 'Blood Test',
        'doctor_name': 'Dr. Alice Smith',
        'hospital_name': 'Metro Health Clinic',
        'report_date': '2026-02-15T10:00:00',
        'description': 'Routine health checkup CBC panel.'
    }
    response = client.post('/api/reports', data=data, content_type='multipart/form-data', headers=alice['headers'])
    assert response.status_code == 201
    json_data = response.get_json()
    assert json_data['report']['reportTitle'] == 'Complete Blood Count (CBC)'
    assert json_data['report']['reportCategory'] == 'Blood Test'
    assert json_data['report']['fileType'] == 'pdf'

# Test 2: Uploading an X-ray image (PNG)
def test_upload_xray_image(client, auth_headers):
    alice = auth_headers['alice']
    png_content = b"\x89PNG\r\n\x1a\nfake png x-ray scan data"
    data = {
        'file': (io.BytesIO(png_content), 'chest_xray.png'),
        'report_title': 'Chest X-Ray AP View',
        'report_category': 'X-ray',
        'doctor_name': 'Dr. Radiologist',
        'hospital_name': 'City Diagnostic Center',
        'report_date': '2026-03-01T14:30:00',
        'description': 'Normal lung fields, clear costophrenic angles.'
    }
    response = client.post('/api/reports', data=data, content_type='multipart/form-data', headers=alice['headers'])
    assert response.status_code == 201
    json_data = response.get_json()
    assert json_data['report']['reportTitle'] == 'Chest X-Ray AP View'
    assert json_data['report']['fileType'] == 'png'

# Test 3: Viewing uploaded reports
def test_view_uploaded_reports(client, auth_headers):
    alice = auth_headers['alice']
    # Upload one report
    pdf_content = b"%PDF-1.5 test document"
    client.post('/api/reports', data={
        'file': (io.BytesIO(pdf_content), 'urine_routine.pdf'),
        'report_title': 'Urine Routine Analysis',
        'report_category': 'Urine Test'
    }, content_type='multipart/form-data', headers=alice['headers'])

    response = client.get('/api/reports', headers=alice['headers'])
    assert response.status_code == 200
    reports = response.get_json()['reports']
    assert len(reports) == 1
    assert reports[0]['reportTitle'] == 'Urine Routine Analysis'

# Test 4: Searching reports by name, doctor, or hospital
def test_search_reports(client, auth_headers):
    alice = auth_headers['alice']
    pdf_data = b"%PDF-1.4 search sample"
    # Upload report 1
    client.post('/api/reports', data={
        'file': (io.BytesIO(pdf_data), 'blood.pdf'),
        'report_title': 'Lipid Profile Screen',
        'report_category': 'Blood Test',
        'doctor_name': 'Dr. Gregory House',
        'hospital_name': 'Princeton Plainsboro'
    }, content_type='multipart/form-data', headers=alice['headers'])

    # Upload report 2
    client.post('/api/reports', data={
        'file': (io.BytesIO(pdf_data), 'mri.pdf'),
        'report_title': 'Brain MRI Scan',
        'report_category': 'MRI Scan',
        'doctor_name': 'Dr. James Wilson',
        'hospital_name': 'Community Hospital'
    }, content_type='multipart/form-data', headers=alice['headers'])

    # Search by title
    res_search = client.get('/api/reports?search=Lipid', headers=alice['headers'])
    assert len(res_search.get_json()['reports']) == 1
    assert res_search.get_json()['reports'][0]['reportTitle'] == 'Lipid Profile Screen'

    # Search by doctor
    res_doc = client.get('/api/reports?search=Wilson', headers=alice['headers'])
    assert len(res_doc.get_json()['reports']) == 1
    assert res_doc.get_json()['reports'][0]['reportTitle'] == 'Brain MRI Scan'

# Test 5: Filtering by category and date
def test_filter_reports_by_category(client, auth_headers):
    alice = auth_headers['alice']
    pdf_data = b"%PDF-1.4 filter sample"
    client.post('/api/reports', data={
        'file': (io.BytesIO(pdf_data), 'ct.pdf'),
        'report_title': 'Abdominal CT',
        'report_category': 'CT Scan'
    }, content_type='multipart/form-data', headers=alice['headers'])

    client.post('/api/reports', data={
        'file': (io.BytesIO(pdf_data), 'rx.pdf'),
        'report_title': 'Cardiology Prescription',
        'report_category': 'Prescription'
    }, content_type='multipart/form-data', headers=alice['headers'])

    # Filter for CT Scan
    res_ct = client.get('/api/reports?category=CT Scan', headers=alice['headers'])
    assert len(res_ct.get_json()['reports']) == 1
    assert res_ct.get_json()['reports'][0]['reportTitle'] == 'Abdominal CT'

    # Filter for Prescription
    res_rx = client.get('/api/reports?category=Prescription', headers=alice['headers'])
    assert len(res_rx.get_json()['reports']) == 1
    assert res_rx.get_json()['reports'][0]['reportTitle'] == 'Cardiology Prescription'

# Test 6: Downloading a report
def test_download_report(client, auth_headers):
    alice = auth_headers['alice']
    original_bytes = b"%PDF-1.4 test download payload for verification"
    res_upload = client.post('/api/reports', data={
        'file': (io.BytesIO(original_bytes), 'download_test.pdf'),
        'report_title': 'Download Test PDF',
        'report_category': 'Blood Test'
    }, content_type='multipart/form-data', headers=alice['headers'])
    report_id = res_upload.get_json()['report']['reportId']

    res_download = client.get(f'/api/reports/{report_id}/download', headers=alice['headers'])
    assert res_download.status_code == 200
    assert res_download.data == original_bytes
    assert res_download.content_type == 'application/pdf'

# Test 7: Deleting reports
def test_delete_report(client, auth_headers):
    alice = auth_headers['alice']
    pdf_data = b"%PDF-1.4 delete test"
    res_upload = client.post('/api/reports', data={
        'file': (io.BytesIO(pdf_data), 'to_delete.pdf'),
        'report_title': 'Report To Delete',
        'report_category': 'Blood Test'
    }, content_type='multipart/form-data', headers=alice['headers'])
    report_id = res_upload.get_json()['report']['reportId']

    # Delete report
    res_del = client.delete(f'/api/reports/{report_id}', headers=alice['headers'])
    assert res_del.status_code == 200

    # Ensure it no longer exists
    res_get = client.get(f'/api/reports/{report_id}', headers=alice['headers'])
    assert res_get.status_code == 404

# Test 8: Patient isolation & Doctor authorization
def test_patient_isolation_and_doctor_authorization(client, auth_headers):
    alice = auth_headers['alice']
    bob = auth_headers['bob']
    doctor = auth_headers['doctor']

    # Alice uploads a report
    pdf_data = b"%PDF-1.4 confidential medical record"
    res_upload = client.post('/api/reports', data={
        'file': (io.BytesIO(pdf_data), 'confidential.pdf'),
        'report_title': 'Confidential Report',
        'report_category': 'Blood Test'
    }, content_type='multipart/form-data', headers=alice['headers'])
    report_id = res_upload.get_json()['report']['reportId']

    # Bob tries to access Alice's report -> 403 Forbidden
    res_bob_get = client.get(f'/api/reports/{report_id}', headers=bob['headers'])
    assert res_bob_get.status_code == 403

    res_bob_dl = client.get(f'/api/reports/{report_id}/download', headers=bob['headers'])
    assert res_bob_dl.status_code == 403

    # Bob tries to delete Alice's report -> 403 Forbidden
    res_bob_del = client.delete(f'/api/reports/{report_id}', headers=bob['headers'])
    assert res_bob_del.status_code == 403

    # Doctor tries to view Alice's report before authorization -> 403 Forbidden
    res_doc_unauth = client.get(f'/api/reports/{report_id}', headers=doctor['headers'])
    assert res_doc_unauth.status_code == 403

    # Alice grants access to Doctor
    res_grant = client.post('/api/auth/grant-access', json={
        'doctorId': doctor['user']['id']
    }, headers=alice['headers'])
    assert res_grant.status_code in (200, 201)

    # Doctor now views Alice's report -> 200 OK
    res_doc_auth = client.get(f'/api/reports/{report_id}', headers=doctor['headers'])
    assert res_doc_auth.status_code == 200
    assert res_doc_auth.get_json()['report']['reportTitle'] == 'Confidential Report'

    # Doctor can download the authorized report
    res_doc_dl = client.get(f'/api/reports/{report_id}/download', headers=doctor['headers'])
    assert res_doc_dl.status_code == 200
    assert res_doc_dl.data == pdf_data

# Test 9: Handling invalid formats, spoofed extensions, and oversized files
def test_invalid_file_formats_and_oversized_files(client, auth_headers):
    alice = auth_headers['alice']

    # 1. Unsupported extension (e.g. .exe or .txt)
    txt_content = b"Plain text file"
    res_bad_ext = client.post('/api/reports', data={
        'file': (io.BytesIO(txt_content), 'notes.txt'),
        'report_title': 'Notes'
    }, content_type='multipart/form-data', headers=alice['headers'])
    assert res_bad_ext.status_code == 400
    assert 'INVALID_FILE_TYPE' in res_bad_ext.get_json()['code']

    # 2. Spoofed extension: claimed to be PDF, but header is not %PDF-
    spoofed_bytes = b"MZ\x90\x00\x03\x00\x00\x00This is an executable renamed to pdf"
    res_spoof = client.post('/api/reports', data={
        'file': (io.BytesIO(spoofed_bytes), 'malware.pdf'),
        'report_title': 'Spoofed PDF'
    }, content_type='multipart/form-data', headers=alice['headers'])
    assert res_spoof.status_code == 400
    assert 'INVALID_FILE_SIGNATURE' in res_spoof.get_json()['code']

    # 3. Oversized file (> 5 MB)
    large_pdf = b"%PDF-1.4" + b"0" * (5 * 1024 * 1024 + 10)
    res_large = client.post('/api/reports', data={
        'file': (io.BytesIO(large_pdf), 'huge.pdf'),
        'report_title': 'Huge Report'
    }, content_type='multipart/form-data', headers=alice['headers'])
    assert res_large.status_code in (400, 413)

# Test 10: Medical History integration
def test_medical_history_report_linking(client, auth_headers):
    alice = auth_headers['alice']

    # Create medical visit record
    res_rec = client.post('/api/records', json={
        'doctorOrHospital': 'Central Clinic',
        'visitDate': '2026-01-20T09:00:00',
        'reason': 'Chronic Cough',
        'diagnosis': 'Bronchitis',
        'prescription': 'Antibiotics for 5 days'
    }, headers=alice['headers'])
    assert res_rec.status_code == 201
    record_id = res_rec.get_json()['record']['recordId']

    # Upload report linked to this medical record
    pdf_bytes = b"%PDF-1.4 sputum culture test"
    res_rep = client.post('/api/reports', data={
        'file': (io.BytesIO(pdf_bytes), 'sputum.pdf'),
        'report_title': 'Sputum Culture',
        'report_category': 'Other medical documents',
        'medical_record_id': record_id
    }, content_type='multipart/form-data', headers=alice['headers'])
    assert res_rep.status_code == 201

    # Fetch reports for the record
    res_linked = client.get(f'/api/records/{record_id}/reports', headers=alice['headers'])
    assert res_linked.status_code == 200
    reports = res_linked.get_json()['reports']
    assert len(reports) == 1
    assert reports[0]['reportTitle'] == 'Sputum Culture'

import os
from datetime import datetime, timezone
import uuid
from flask import Blueprint, request, jsonify, current_app, send_file
from werkzeug.utils import secure_filename
from database import db
from models import MedicalReport, DoctorPatientAccess, MedicalRecord
from auth import token_required
from utils.security import (
    allowed_file,
    get_file_extension,
    validate_file_signature,
    secure_random_filename,
    is_safe_path,
    get_patient_storage_dir
)

report_bp = Blueprint('reports', __name__, url_prefix='/api/reports')

def utc_now():
    return datetime.now(timezone.utc)

VALID_CATEGORIES = {
    'Blood Test',
    'Blood test',
    'Urine Test',
    'Urine test',
    'X-ray',
    'MRI Scan',
    'CT Scan',
    'Prescription',
    'Other medical documents',
    'Other medical document'
}

def check_report_access(report: MedicalReport, user) -> bool:
    """Check if user is authorized to view/download this report."""
    if user.role == 'Admin':
        return True
    if user.role == 'Patient' and report.patient_id == user.id:
        return True
    if user.role == 'Doctor':
        # Check if doctor was granted access by the patient
        access = DoctorPatientAccess.query.filter_by(
            patient_id=report.patient_id,
            doctor_id=user.id
        ).first()
        return access is not None
    return False

@report_bp.route('', methods=['POST'])
@token_required
def upload_report(current_user):
    """
    Upload a medical report. Only patients (or admins on patient behalf) can upload.
    Enforces file type, signature, size limits, and randomized secure storage.
    """
    if current_user.role not in ('Patient', 'Admin'):
        return jsonify({'error': 'Only patients can upload medical reports', 'code': 'FORBIDDEN'}), 403

    # Check for file
    if 'file' not in request.files:
        return jsonify({'error': 'No file part provided in request', 'code': 'NO_FILE'}), 400

    file = request.files['file']
    if not file or not file.filename:
        return jsonify({'error': 'No file selected for upload', 'code': 'EMPTY_FILENAME'}), 400

    filename = secure_filename(file.filename)
    if not allowed_file(filename):
        return jsonify({
            'error': 'Unsupported file format. Only PDF, JPG, JPEG, and PNG files are allowed.',
            'code': 'INVALID_FILE_TYPE'
        }), 400

    extension = get_file_extension(filename)

    # Validate file size (enforce MAX_CONTENT_LENGTH or 5MB)
    max_size = current_app.config.get('MAX_CONTENT_LENGTH', 5 * 1024 * 1024)
    file.seek(0, os.SEEK_END)
    file_size = file.tell()
    file.seek(0)

    if file_size <= 0:
        return jsonify({'error': 'Uploaded file is empty', 'code': 'FILE_EMPTY'}), 400

    if file_size > max_size:
        return jsonify({
            'error': f'File exceeds maximum allowed size of {max_size // (1024 * 1024)} MB',
            'code': 'FILE_TOO_LARGE'
        }), 400

    # Validate file signature / magic numbers against extension
    header_bytes = file.read(16)
    file.seek(0)
    if not validate_file_signature(header_bytes, extension):
        return jsonify({
            'error': 'File signature does not match extension. Spoofed or corrupt files are rejected.',
            'code': 'INVALID_FILE_SIGNATURE'
        }), 400

    # Extract metadata fields
    patient_id = current_user.id
    if current_user.role == 'Admin' and request.form.get('patient_id'):
        patient_id = request.form.get('patient_id').strip()

    report_title = (request.form.get('report_title') or request.form.get('reportTitle') or filename).strip()
    report_category = (request.form.get('report_category') or request.form.get('reportCategory') or 'Other medical documents').strip()
    doctor_name = (request.form.get('doctor_name') or request.form.get('doctorName') or '').strip()
    hospital_name = (request.form.get('hospital_name') or request.form.get('hospitalName') or '').strip()
    description = (request.form.get('description') or request.form.get('notes') or '').strip()
    medical_record_id = (request.form.get('medical_record_id') or request.form.get('recordId') or '').strip() or None

    report_date_raw = request.form.get('report_date') or request.form.get('reportDate')
    report_date = utc_now()
    if report_date_raw:
        try:
            report_date = datetime.fromisoformat(report_date_raw.replace('Z', '+00:00'))
        except Exception:
            try:
                report_date = datetime.strptime(report_date_raw, '%Y-%m-%d').replace(tzinfo=timezone.utc)
            except Exception:
                pass

    # Secure randomized file storage
    base_upload_dir = current_app.config['UPLOAD_FOLDER']
    patient_dir = get_patient_storage_dir(base_upload_dir, patient_id)
    random_filename = secure_random_filename(filename)
    dest_path = os.path.join(patient_dir, random_filename)

    # Path traversal protection
    if not is_safe_path(base_upload_dir, dest_path):
        return jsonify({'error': 'Invalid target file path', 'code': 'PATH_TRAVERSAL_DETECTED'}), 400

    try:
        file.save(dest_path)
    except Exception as e:
        return jsonify({'error': f'Failed to save file: {str(e)}', 'code': 'STORAGE_ERROR'}), 500

    # Save to database
    report_id = str(uuid.uuid4())
    report = MedicalReport(
        report_id=report_id,
        patient_id=patient_id,
        medical_record_id=medical_record_id,
        report_title=report_title,
        report_category=report_category,
        doctor_name=doctor_name,
        hospital_name=hospital_name,
        report_date=report_date,
        file_name=filename,
        file_path=dest_path,
        file_type=extension,
        description=description,
        uploaded_at=utc_now()
    )

    try:
        db.session.add(report)
        db.session.commit()
    except Exception as e:
        # Cleanup uploaded file on DB failure
        if os.path.exists(dest_path):
            try:
                os.remove(dest_path)
            except Exception:
                pass
        return jsonify({'error': f'Database error saving report: {str(e)}', 'code': 'DB_ERROR'}), 500

    return jsonify({
        'message': 'Medical report uploaded successfully',
        'report': report.to_dict()
    }), 201

@report_bp.route('', methods=['GET'])
@token_required
def list_reports(current_user):
    """
    Retrieve medical reports with smart filtering, searching, and sorting.
    Patients see only their own reports.
    Doctors can see a patient's reports only if authorized.
    """
    target_patient_id = None

    if current_user.role == 'Patient':
        target_patient_id = current_user.id
    elif current_user.role == 'Doctor':
        target_patient_id = request.args.get('patient_id') or request.args.get('patientId')
        if not target_patient_id:
            return jsonify({'error': 'patient_id parameter is required for doctor access', 'code': 'MISSING_PATIENT_ID'}), 400
        # Verify authorization
        access = DoctorPatientAccess.query.filter_by(
            patient_id=target_patient_id,
            doctor_id=current_user.id
        ).first()
        if not access:
            return jsonify({
                'error': 'You are not authorized by this patient to view their medical records/reports.',
                'code': 'UNAUTHORIZED_DOCTOR_ACCESS'
            }), 403
    elif current_user.role == 'Admin':
        target_patient_id = request.args.get('patient_id') or request.args.get('patientId')

    query = MedicalReport.query

    if target_patient_id:
        query = query.filter_by(patient_id=target_patient_id)

    # Optional filter by medical record
    record_id = request.args.get('medical_record_id') or request.args.get('recordId')
    if record_id:
        query = query.filter_by(medical_record_id=record_id)

    # Category filter
    category = request.args.get('category')
    if category and category != 'All reports':
        query = query.filter(MedicalReport.report_category.ilike(category))

    # Search filter (report name, doctor, hospital)
    search = request.args.get('search')
    if search:
        search_term = f"%{search.strip()}%"
        query = query.filter(
            (MedicalReport.report_title.ilike(search_term)) |
            (MedicalReport.doctor_name.ilike(search_term)) |
            (MedicalReport.hospital_name.ilike(search_term))
        )

    # Date range filter
    start_date_str = request.args.get('start_date') or request.args.get('startDate')
    end_date_str = request.args.get('end_date') or request.args.get('endDate')
    if start_date_str:
        try:
            start_date = datetime.fromisoformat(start_date_str.replace('Z', '+00:00'))
            query = query.filter(MedicalReport.report_date >= start_date)
        except Exception:
            pass
    if end_date_str:
        try:
            end_date = datetime.fromisoformat(end_date_str.replace('Z', '+00:00'))
            query = query.filter(MedicalReport.report_date <= end_date)
        except Exception:
            pass

    # Sorting
    sort_order = request.args.get('sort', 'newest').lower()
    if sort_order == 'oldest':
        query = query.order_by(MedicalReport.report_date.asc())
    else:
        query = query.order_by(MedicalReport.report_date.desc(), MedicalReport.uploaded_at.desc())

    reports = query.all()
    return jsonify({
        'total': len(reports),
        'reports': [r.to_dict() for r in reports]
    }), 200

@report_bp.route('/<report_id>', methods=['GET'])
@token_required
def get_report(current_user, report_id):
    """Retrieve details for a single report after authorization check."""
    report = db.session.get(MedicalReport, report_id)
    if not report:
        return jsonify({'error': 'Report not found', 'code': 'REPORT_NOT_FOUND'}), 404

    if not check_report_access(report, current_user):
        return jsonify({'error': 'Access denied to this report', 'code': 'FORBIDDEN'}), 403

    return jsonify({'report': report.to_dict()}), 200

@report_bp.route('/<report_id>', methods=['PUT'])
@token_required
def update_report(current_user, report_id):
    """Update report metadata. Only the owner patient or admin can update."""
    report = db.session.get(MedicalReport, report_id)
    if not report:
        return jsonify({'error': 'Report not found', 'code': 'REPORT_NOT_FOUND'}), 404

    if current_user.role != 'Admin' and report.patient_id != current_user.id:
        return jsonify({'error': 'You can only edit your own reports', 'code': 'FORBIDDEN'}), 403

    data = request.get_json() or {}

    if 'reportTitle' in data or 'report_title' in data:
        report.report_title = (data.get('reportTitle') or data.get('report_title') or report.report_title).strip()
    if 'reportCategory' in data or 'report_category' in data:
        report.report_category = (data.get('reportCategory') or data.get('report_category') or report.report_category).strip()
    if 'doctorName' in data or 'doctor_name' in data:
        report.doctor_name = (data.get('doctorName') or data.get('doctor_name') or '').strip()
    if 'hospitalName' in data or 'hospital_name' in data:
        report.hospital_name = (data.get('hospitalName') or data.get('hospital_name') or '').strip()
    if 'description' in data:
        report.description = (data.get('description') or '').strip()
    if 'medicalRecordId' in data or 'recordId' in data:
        val = data.get('medicalRecordId') or data.get('recordId')
        report.medical_record_id = val.strip() if val else None

    date_raw = data.get('reportDate') or data.get('report_date')
    if date_raw:
        try:
            report.report_date = datetime.fromisoformat(date_raw.replace('Z', '+00:00'))
        except Exception:
            pass

    db.session.commit()
    return jsonify({
        'message': 'Report updated successfully',
        'report': report.to_dict()
    }), 200

@report_bp.route('/<report_id>', methods=['DELETE'])
@token_required
def delete_report(current_user, report_id):
    """Delete a report and its underlying file after confirmation."""
    report = db.session.get(MedicalReport, report_id)
    if not report:
        return jsonify({'error': 'Report not found', 'code': 'REPORT_NOT_FOUND'}), 404

    if current_user.role != 'Admin' and report.patient_id != current_user.id:
        return jsonify({'error': 'You can only delete your own reports', 'code': 'FORBIDDEN'}), 403

    file_path = report.file_path
    db.session.delete(report)
    db.session.commit()

    # Safely remove underlying file
    if file_path and os.path.exists(file_path):
        try:
            os.remove(file_path)
        except Exception:
            pass

    return jsonify({'message': 'Report deleted successfully'}), 200

@report_bp.route('/<report_id>/download', methods=['GET'])
@token_required
def download_report(current_user, report_id):
    """
    Download or stream the report file.
    Protected against path traversal and unauthorized access.
    Never exposes public URL.
    """
    report = db.session.get(MedicalReport, report_id)
    if not report:
        return jsonify({'error': 'Report not found', 'code': 'REPORT_NOT_FOUND'}), 404

    if not check_report_access(report, current_user):
        return jsonify({'error': 'Access denied to download this report', 'code': 'FORBIDDEN'}), 403

    base_upload_dir = current_app.config['UPLOAD_FOLDER']
    file_path = report.file_path

    if not file_path or not os.path.exists(file_path):
        return jsonify({'error': 'Report file does not exist on disk', 'code': 'FILE_NOT_FOUND'}), 404

    # Path traversal protection
    if not is_safe_path(base_upload_dir, file_path):
        return jsonify({'error': 'Security violation: Path traversal prevented', 'code': 'PATH_TRAVERSAL_DETECTED'}), 403

    ext = report.file_type.lower()
    mime_type_map = {
        'pdf': 'application/pdf',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png'
    }
    mimetype = mime_type_map.get(ext, 'application/octet-stream')

    as_attachment = request.args.get('attachment', 'false').lower() == 'true'

    return send_file(
        file_path,
        mimetype=mimetype,
        as_attachment=as_attachment,
        download_name=report.file_name
    )

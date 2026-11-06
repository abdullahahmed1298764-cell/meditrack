from datetime import datetime, timezone
import uuid
from flask import Blueprint, request, jsonify
from database import db
from models import MedicalRecord, MedicalReport, DoctorPatientAccess
from auth import token_required

record_bp = Blueprint('records', __name__, url_prefix='/api/records')

def utc_now():
    return datetime.now(timezone.utc)

@record_bp.route('', methods=['GET'])
@token_required
def list_records(current_user):
    target_patient_id = None

    if current_user.role == 'Patient':
        target_patient_id = current_user.id
    elif current_user.role == 'Doctor':
        target_patient_id = request.args.get('patient_id') or request.args.get('patientId')
        if not target_patient_id:
            return jsonify({'error': 'patient_id is required', 'code': 'MISSING_PATIENT_ID'}), 400
        # Check authorization
        access = DoctorPatientAccess.query.filter_by(
            patient_id=target_patient_id,
            doctor_id=current_user.id
        ).first()
        if not access:
            return jsonify({'error': 'Unauthorized doctor access', 'code': 'FORBIDDEN'}), 403
    elif current_user.role == 'Admin':
        target_patient_id = request.args.get('patient_id') or request.args.get('patientId')

    query = MedicalRecord.query
    if target_patient_id:
        query = query.filter_by(patient_id=target_patient_id)

    records = query.order_by(MedicalRecord.visit_date.desc()).all()
    return jsonify({
        'total': len(records),
        'records': [r.to_dict() for r in records]
    }), 200

@record_bp.route('', methods=['POST'])
@token_required
def create_record(current_user):
    if current_user.role not in ('Patient', 'Admin'):
        return jsonify({'error': 'Only patients can create records', 'code': 'FORBIDDEN'}), 403

    data = request.get_json() or {}
    patient_id = current_user.id if current_user.role == 'Patient' else (data.get('patientId') or current_user.id)
    doctor_or_hospital = (data.get('doctorOrHospital') or data.get('doctor_or_hospital') or '').strip()
    reason = (data.get('reason') or '').strip()
    diagnosis = (data.get('diagnosis') or '').strip()
    prescription = (data.get('prescription') or '').strip()

    if not doctor_or_hospital or not reason:
        return jsonify({'error': 'Doctor/Hospital and reason are required', 'code': 'VALIDATION_ERROR'}), 400

    visit_date_raw = data.get('visitDate') or data.get('visit_date')
    visit_date = utc_now()
    if visit_date_raw:
        try:
            visit_date = datetime.fromisoformat(visit_date_raw.replace('Z', '+00:00'))
        except Exception:
            pass

    record_id = data.get('recordId') or str(uuid.uuid4())
    record = MedicalRecord(
        record_id=record_id,
        patient_id=patient_id,
        doctor_or_hospital=doctor_or_hospital,
        visit_date=visit_date,
        reason=reason,
        diagnosis=diagnosis,
        prescription=prescription,
        created_at=utc_now()
    )

    db.session.add(record)
    db.session.commit()
    return jsonify({'message': 'Record created successfully', 'record': record.to_dict()}), 201

@record_bp.route('/<record_id>/reports', methods=['GET'])
@token_required
def get_record_reports(current_user, record_id):
    """Retrieve all reports linked to a medical history record."""
    record = db.session.get(MedicalRecord, record_id)
    if not record:
        return jsonify({'error': 'Record not found', 'code': 'RECORD_NOT_FOUND'}), 404

    # Authorization
    if current_user.role == 'Patient' and record.patient_id != current_user.id:
        return jsonify({'error': 'Access denied', 'code': 'FORBIDDEN'}), 403
    elif current_user.role == 'Doctor':
        access = DoctorPatientAccess.query.filter_by(
            patient_id=record.patient_id,
            doctor_id=current_user.id
        ).first()
        if not access:
            return jsonify({'error': 'Doctor not authorized by patient', 'code': 'FORBIDDEN'}), 403

    reports = MedicalReport.query.filter_by(medical_record_id=record_id).order_by(MedicalReport.report_date.desc()).all()
    return jsonify({
        'recordId': record_id,
        'total': len(reports),
        'reports': [r.to_dict() for r in reports]
    }), 200
